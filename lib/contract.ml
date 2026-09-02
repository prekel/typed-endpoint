open! Base

module Documentation = struct
  type t =
    { description : string
    ; tags : string list
    }

  let v ?(tags = []) ~description () = { description; tags }
end

module Operation_metadata = struct
  type t =
    { description : string
    ; summary : string option
    ; tags : string list
    ; deprecated : bool
    ; operation_id : string option
    }

  let v ?summary ?(tags = []) ?(deprecated = false) ?operation_id ~description () =
    { description; summary; tags; deprecated; operation_id }
  ;;
end

type param_kind =
  [ `Path
  | `Query
  ]

type param =
  { name : string
  ; kind : param_kind
  ; required : bool
  ; schema : Ppx_deriving_jsonschema_runtime.t
  ; metadata : Documentation.t
  }

type request_body =
  | No_body
  | Json_body of
      { schema : Ppx_deriving_jsonschema_runtime.t
      ; metadata : Documentation.t
      }
  | Text_body of { metadata : Documentation.t }

type response_content =
  | Text
  | Json of Ppx_deriving_jsonschema_runtime.t

type response_payload =
  { metadata : Documentation.t
  ; content : response_content list
  }

type response =
  { status : int
  ; payload : response_payload
  }

type endpoint =
  { meth : string
  ; path : string
  ; metadata : Operation_metadata.t option
  ; params : param list
  ; request_body : request_body
  ; responses : response list
  ; parse_error_response : response option
  ; response_families : int list list
  ; has_parsers : bool
  }

type route =
  { meth : string
  ; path : string
  ; endpoint : endpoint option
  }

type group =
  { prefix : string list
  ; metadata : Operation_metadata.t
  ; routes : route list
  }

module Compile_error = struct
  type t =
    | Duplicate_route of
        { meth : string
        ; path : string
        }
    | Duplicate_operation_id of string
    | Duplicate_response_status of
        { meth : string
        ; path : string
        ; status : int
        }
    | Empty_response_family of
        { meth : string
        ; path : string
        }
    | Invalid_no_content_response of
        { meth : string
        ; path : string
        }
    | Missing_parse_error_policy of
        { meth : string
        ; path : string
        }

  let to_string = function
    | Duplicate_route { meth; path } -> "duplicate route: " ^ meth ^ " " ^ path
    | Duplicate_operation_id operation_id -> "duplicate operationId: " ^ operation_id
    | Duplicate_response_status { meth; path; status } ->
      "duplicate response status " ^ Int.to_string status ^ ": " ^ meth ^ " " ^ path
    | Empty_response_family { meth; path } ->
      "empty response status family: " ^ meth ^ " " ^ path
    | Invalid_no_content_response { meth; path } ->
      "204 response must use an empty payload: " ^ meth ^ " " ^ path
    | Missing_parse_error_policy { meth; path } ->
      "missing parse-error policy: " ^ meth ^ " " ^ path
  ;;
end

module Compiled = struct
  type compiled_route =
    { meth : string
    ; path : string
    ; endpoint : endpoint option
    }

  type compiled_group =
    { metadata : Operation_metadata.t
    ; routes : compiled_route list
    }

  type t = { groups : compiled_group list }

  let groups t = t.groups
end

let prefix_to_string = function
  | [] -> ""
  | segments -> "/" ^ String.concat ~sep:"/" segments
;;

let full_path ~prefix path =
  if String.is_empty prefix then
    path
  else
    prefix ^ path
;;

let duplicate_statuses statuses =
  let seen = Hash_set.create (module Int) in
  List.filter statuses ~f:(fun status ->
    if Hash_set.mem seen status then
      true
    else (
      Hash_set.add seen status;
      false))
;;

let schema_equal
      (left : Ppx_deriving_jsonschema_runtime.t)
      (right : Ppx_deriving_jsonschema_runtime.t)
  =
  Yojson.Safe.equal (left :> Yojson.Safe.t) (right :> Yojson.Safe.t)
;;

let deduplicate_schemas (schemas : Ppx_deriving_jsonschema_runtime.t list)
  : Ppx_deriving_jsonschema_runtime.t list
  =
  List.fold schemas ~init:[] ~f:(fun unique schema ->
    if List.exists unique ~f:(schema_equal schema) then
      unique
    else
      unique @ [ schema ])
;;

let merge_payloads primary secondary =
  let contents = primary.content @ secondary.content in
  let has_text =
    List.exists contents ~f:(function
      | Text -> true
      | Json _ -> false)
  in
  let schemas =
    List.filter_map contents ~f:(function
      | Text -> None
      | Json schema -> Some schema)
    |> deduplicate_schemas
  in
  let json_content =
    match schemas with
    | [] -> []
    | [ schema ] -> [ Json schema ]
    | schemas ->
      let schema : Ppx_deriving_jsonschema_runtime.t =
        `Assoc [ "oneOf", `List schemas ]
      in
      [ Json schema ]
  in
  { primary with
    content =
      (if has_text then
         [ Text ]
       else
         [])
      @ json_content
  }
;;

let add_parse_error_response (endpoint : endpoint) =
  if not endpoint.has_parsers then
    { endpoint with parse_error_response = None }
  else (
    match
      endpoint.parse_error_response
    with
    | None -> endpoint
    | Some parse_response ->
      let found = ref false in
      let responses =
        List.map endpoint.responses ~f:(fun response ->
          if Int.equal response.status parse_response.status then (
            found := true;
            { response with
              payload = merge_payloads response.payload parse_response.payload
            })
          else
            response)
      in
      let responses =
        if !found then
          responses
        else
          responses @ [ parse_response ]
      in
      { endpoint with responses; parse_error_response = None })
;;

let compile (groups : group list) : (Compiled.t, Compile_error.t list) Result.t =
  let routes_seen = Hash_set.create (module String) in
  let operation_ids = Hash_set.create (module String) in
  let errors = ref [] in
  let add_error error = errors := error :: !errors in
  let compiled_groups =
    List.map groups ~f:(fun group ->
      let prefix = prefix_to_string group.prefix in
      let routes =
        List.map group.routes ~f:(fun route ->
          let path = full_path ~prefix route.path in
          let route_key = route.meth ^ " " ^ path in
          if Hash_set.mem routes_seen route_key then
            add_error (Compile_error.Duplicate_route { meth = route.meth; path })
          else
            Hash_set.add routes_seen route_key;
          Option.iter route.endpoint ~f:(fun endpoint ->
            Option.iter endpoint.metadata ~f:(fun metadata ->
              Option.iter metadata.operation_id ~f:(fun operation_id ->
                if Hash_set.mem operation_ids operation_id then
                  add_error (Compile_error.Duplicate_operation_id operation_id)
                else
                  Hash_set.add operation_ids operation_id));
            if endpoint.has_parsers && Option.is_none endpoint.parse_error_response then
              add_error
                (Compile_error.Missing_parse_error_policy { meth = route.meth; path });
            if List.exists endpoint.response_families ~f:List.is_empty then
              add_error (Compile_error.Empty_response_family { meth = route.meth; path });
            let statuses =
              List.map endpoint.responses ~f:(fun response -> response.status)
            in
            List.iter endpoint.responses ~f:(fun response ->
              match response.status, response.payload.content with
              | 204, [] -> ()
              | 204, _ :: _ ->
                add_error
                  (Compile_error.Invalid_no_content_response { meth = route.meth; path })
              | _ -> ());
            duplicate_statuses statuses
            |> List.iter ~f:(fun status ->
              add_error
                (Compile_error.Duplicate_response_status
                   { meth = route.meth; path; status })));
          { Compiled.meth = route.meth
          ; path
          ; endpoint = Option.map route.endpoint ~f:add_parse_error_response
          })
      in
      { Compiled.metadata = group.metadata; routes })
  in
  match List.rev !errors with
  | [] -> Ok { Compiled.groups = compiled_groups }
  | errors -> Error errors
;;

let compile_exn groups =
  match compile groups with
  | Ok compiled -> compiled
  | Error errors ->
    errors |> List.map ~f:Compile_error.to_string |> String.concat ~sep:"; " |> failwith
;;
