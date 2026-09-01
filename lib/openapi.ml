open! Base

module type Metadata = sig
  type t

  val description : t -> string
  val summary : t -> string option
  val tags : t -> string list
  val deprecated : t -> bool
  val operation_id : t -> string option
end

module Make (Metadata : Metadata) = struct
  type param_kind =
    [ `Path
    | `Query
    ]

  type param_spec =
    { name : string
    ; kind : param_kind
    ; required : bool
    ; schema : Ppx_deriving_jsonschema_runtime.t
    ; meta : Metadata.t
    }

  type request_body_spec =
    | No_body
    | Json_body of
        { schema : Ppx_deriving_jsonschema_runtime.t
        ; meta : Metadata.t
        }
    | Text_body of { meta : Metadata.t }

  type response_payload_spec =
    | Resp_empty of { meta : Metadata.t }
    | Resp_text of { meta : Metadata.t }
    | Resp_json of
        { schema : Ppx_deriving_jsonschema_runtime.t
        ; meta : Metadata.t
        }

  type response_spec =
    { status : int
    ; payload : response_payload_spec
    }

  type endpoint =
    { meth : string
    ; path : string
    ; operation_meta : Metadata.t option
    ; params : param_spec list
    ; request_body : request_body_spec
    ; responses : response_spec list
    }

  type group =
    { group_meta : Metadata.t
    ; prefix : string list
    ; endpoints : endpoint list
    }

  let path_to_openapi (path : string) : string =
    let segments =
      String.split ~on:'/' path
      |> List.map ~f:(fun segment ->
        if String.is_prefix segment ~prefix:":" then
          "{" ^ String.drop_prefix segment 1 ^ "}"
        else
          segment)
    in
    String.concat ~sep:"/" segments
  ;;

  let prefix_to_string (segments : string list) : string =
    match segments with
    | [] -> ""
    | _ -> "/" ^ String.concat ~sep:"/" segments
  ;;

  let yo_str value = `String value
  let yo_bool value = `Bool value
  let yo_list values = `List values
  let yo_obj fields = `Assoc fields

  let yo_schema (schema : Ppx_deriving_jsonschema_runtime.t) : Yojson.Safe.t =
    (schema :> Yojson.Safe.t)
  ;;

  let render_param (param : param_spec) : Yojson.Safe.t =
    yo_obj
      [ "name", yo_str param.name
      ; ( "in"
        , yo_str
            (match param.kind with
             | `Path -> "path"
             | `Query -> "query") )
      ; "required", yo_bool param.required
      ; "description", yo_str (Metadata.description param.meta)
      ; "schema", yo_schema param.schema
      ]
  ;;

  let render_request_body (request_body : request_body_spec) : Yojson.Safe.t option =
    match request_body with
    | No_body -> None
    | Text_body { meta } ->
      Some
        (yo_obj
           [ "required", yo_bool true
           ; "description", yo_str (Metadata.description meta)
           ; ( "content"
             , yo_obj
                 [ "text/plain", yo_obj [ "schema", yo_obj [ "type", yo_str "string" ] ] ]
             )
           ])
    | Json_body { schema; meta } ->
      Some
        (yo_obj
           [ "required", yo_bool true
           ; "description", yo_str (Metadata.description meta)
           ; ( "content"
             , yo_obj [ "application/json", yo_obj [ "schema", yo_schema schema ] ] )
           ])
  ;;

  let render_response_payload (payload : response_payload_spec) : Yojson.Safe.t =
    match payload with
    | Resp_empty { meta } -> yo_obj [ "description", yo_str (Metadata.description meta) ]
    | Resp_text { meta } ->
      yo_obj
        [ "description", yo_str (Metadata.description meta)
        ; ( "content"
          , yo_obj
              [ "text/plain", yo_obj [ "schema", yo_obj [ "type", yo_str "string" ] ] ] )
        ]
    | Resp_json { schema; meta } ->
      yo_obj
        [ "description", yo_str (Metadata.description meta)
        ; "content", yo_obj [ "application/json", yo_obj [ "schema", yo_schema schema ] ]
        ]
  ;;

  type operation_metadata =
    { description : string
    ; summary : string option
    ; tags : string list
    ; deprecated : bool
    ; operation_id : string option
    }

  let operation_metadata ~(group : Metadata.t) ~(operation : Metadata.t option)
    : operation_metadata
    =
    match operation with
    | None ->
      { description = Metadata.description group
      ; summary = Metadata.summary group
      ; tags = Metadata.tags group
      ; deprecated = Metadata.deprecated group
      ; operation_id = Metadata.operation_id group
      }
    | Some operation ->
      { description = Metadata.description operation
      ; summary = Metadata.summary operation
      ; tags =
          List.dedup_and_sort
            ~compare:String.compare
            (Metadata.tags group @ Metadata.tags operation)
      ; deprecated = Metadata.deprecated operation
      ; operation_id = Metadata.operation_id operation
      }
  ;;

  let render_operation ~(group_meta : Metadata.t) (endpoint : endpoint) : Yojson.Safe.t =
    let metadata =
      operation_metadata ~group:group_meta ~operation:endpoint.operation_meta
    in
    let params = yo_list (List.map endpoint.params ~f:render_param) in
    let request_body = render_request_body endpoint.request_body in
    let responses =
      endpoint.responses
      |> List.map ~f:(fun response ->
        Int.to_string response.status, render_response_payload response.payload)
      |> yo_obj
    in
    let base = [ "parameters", params; "responses", responses ] in
    let base =
      match request_body with
      | None -> base
      | Some request_body -> ("requestBody", request_body) :: base
    in
    yo_obj
      (List.concat
         [ [ "description", yo_str metadata.description ]
         ; (match metadata.summary with
            | None -> []
            | Some summary -> [ "summary", yo_str summary ])
         ; (if List.is_empty metadata.tags then
              []
            else
              [ "tags", yo_list (List.map metadata.tags ~f:yo_str) ])
         ; (if metadata.deprecated then
              [ "deprecated", yo_bool true ]
            else
              [])
         ; (match metadata.operation_id with
            | None -> []
            | Some operation_id -> [ "operationId", yo_str operation_id ])
         ; base
         ])
  ;;

  let render ?(title = "API") ?(version = "0.1.0") (groups : group list) : Yojson.Safe.t =
    let tags =
      groups
      |> List.concat_map ~f:(fun group ->
        List.map (Metadata.tags group.group_meta) ~f:(fun name ->
          yo_obj
            [ "name", yo_str name
            ; "description", yo_str (Metadata.description group.group_meta)
            ]))
      |> fun tags ->
      let unique = Hashtbl.create (module String) in
      List.iter tags ~f:(function
        | `Assoc fields as tag ->
          (match List.Assoc.find fields ~equal:String.equal "name" with
           | Some (`String name) ->
             if not (Hashtbl.mem unique name) then
               Hashtbl.set unique ~key:name ~data:tag
           | _ -> ())
        | _ -> ());
      Hashtbl.data unique |> yo_list
    in
    let by_path = Hashtbl.create (module String) in
    List.iter groups ~f:(fun group ->
      let prefix = prefix_to_string group.prefix in
      List.iter group.endpoints ~f:(fun endpoint ->
        let full_runtime_path =
          if String.is_empty prefix then
            endpoint.path
          else
            prefix ^ endpoint.path
        in
        let path_key = path_to_openapi full_runtime_path in
        let operation =
          render_operation
            ~group_meta:group.group_meta
            { endpoint with path = full_runtime_path }
        in
        Hashtbl.update by_path path_key ~f:(function
          | None -> Map.singleton (module String) endpoint.meth operation
          | Some methods -> Map.set methods ~key:endpoint.meth ~data:operation)));
    let paths =
      Hashtbl.to_alist by_path
      |> List.map ~f:(fun (path, methods) ->
        let methods_json =
          Map.to_alist methods |> List.map ~f:(fun (key, value) -> key, value) |> yo_obj
        in
        path, methods_json)
      |> yo_obj
    in
    yo_obj
      [ "openapi", yo_str "3.1.0"
      ; "info", yo_obj [ "title", yo_str title; "version", yo_str version ]
      ; "tags", tags
      ; "paths", paths
      ]
  ;;
end
