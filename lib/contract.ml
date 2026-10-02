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

module Schema = struct
  type t =
    { value : Json_schema.packed
    ; name : string option
    }

  let v ?name value = { value = Json_schema.pack value; name }

  let equal left right =
    Option.equal String.equal left.name right.name
    && Json_schema.equal_packed left.value right.value
  ;;
end

module Security = struct
  module Scheme = struct
    type api_key_location =
      [ `Header
      | `Query
      | `Cookie
      ]

    type kind =
      | Api_key of
          { parameter : string
          ; location : api_key_location
          }
      | Http_bearer of { bearer_format : string option }
      | Oauth2_implicit of
          { authorization_url : string
          ; scopes : (string * string) list
          }

    type t =
      { name : string
      ; description : string
      ; kind : kind
      }

    let api_key ~name ~parameter ~location ~description () =
      { name; description; kind = Api_key { parameter; location } }
    ;;

    let http_bearer ~name ?bearer_format ~description () =
      { name; description; kind = Http_bearer { bearer_format } }
    ;;

    let oauth2_implicit ~name ~authorization_url ~scopes ~description () =
      { name; description; kind = Oauth2_implicit { authorization_url; scopes } }
    ;;

    let equal left right = Poly.equal left right
  end

  type requirement = (Scheme.t * string list) list

  let require ?(scopes = []) scheme = [ scheme, scopes ]

  let all requirements =
    List.concat requirements
    |> List.fold ~init:[] ~f:(fun combined (scheme, scopes) ->
      match
        List.findi combined ~f:(fun _ (existing, _scopes) ->
          String.equal existing.Scheme.name scheme.Scheme.name
          && Scheme.equal existing scheme)
      with
      | None -> combined @ [ scheme, List.dedup_and_sort scopes ~compare:String.compare ]
      | Some (index, (existing, existing_scopes)) ->
        let merged_scopes =
          List.dedup_and_sort (existing_scopes @ scopes) ~compare:String.compare
        in
        List.mapi combined ~f:(fun current item ->
          if Int.equal current index then
            existing, merged_scopes
          else
            item))
  ;;

  let combine_alternatives left right =
    match left, right with
    | [], alternatives | alternatives, [] -> alternatives
    | left, right ->
      List.concat_map left ~f:(fun left_requirement ->
        List.map right ~f:(fun right_requirement ->
          all [ left_requirement; right_requirement ]))
  ;;
end

module Openapi = struct
  module Server = struct
    type t =
      { url : string
      ; description : string option
      }

    let v ~url ?description () = { url; description }
  end

  module Config = struct
    type t =
      { title : string
      ; version : string
      ; description : string option
      ; servers : Server.t list
      }

    let v ~title ~version ?description ?(servers = []) () =
      { title; version; description; servers }
    ;;

    let default = v ~title:"API" ~version:"0.1.0" ()
  end
end

type param_kind =
  [ `Path
  | `Query
  | `Header
  ]

type param =
  { name : string
  ; kind : param_kind
  ; required : bool
  ; schema : Schema.t
  ; metadata : Documentation.t
  }

type request_body =
  | No_body
  | Json_body of
      { schema : Schema.t
      ; metadata : Documentation.t
      ; max_body_bytes : int
      }
  | Text_body of
      { metadata : Documentation.t
      ; max_body_bytes : int
      }
  | Binary_body of
      { metadata : Documentation.t
      ; max_body_bytes : int
      }

type response_content =
  | Text
  | Json of Schema.t list

type response_header =
  { name : string
  ; required : bool
  ; schema : Schema.t
  ; metadata : Documentation.t
  }

type response_payload =
  { metadata : Documentation.t
  ; content : response_content list
  ; headers : response_header list
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
  ; decode_error_responses : response list
  ; context_responses : response list
  ; security : Security.requirement list
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
    | Ambiguous_route of
        { meth : string
        ; path : string
        ; conflicts_with : string
        }
    | Invalid_group_prefix_segment of string
    | Invalid_route_path of
        { meth : string
        ; path : string
        }
    | Mismatched_path_parameters of
        { meth : string
        ; path : string
        ; declared : string list
        ; captures : string list
        }
    | Duplicate_operation_id of string
    | Duplicate_parameter of
        { meth : string
        ; path : string
        ; kind : param_kind
        ; name : string
        }
    | Duplicate_response_status of
        { meth : string
        ; path : string
        ; status : int
        }
    | Invalid_response_status of
        { meth : string
        ; path : string
        ; status : int
        }
    | Invalid_no_content_response of
        { meth : string
        ; path : string
        }
    | Invalid_body_limit of
        { meth : string
        ; path : string
        ; max_body_bytes : int
        }
    | Invalid_header_name of
        { meth : string
        ; path : string
        ; name : string
        }
    | Duplicate_response_header of
        { meth : string
        ; path : string
        ; status : int
        ; name : string
        }
    | Conflicting_response_header of
        { meth : string
        ; path : string
        ; status : int
        ; name : string
        }
    | Invalid_schema_name of string
    | Conflicting_schema of string
    | Invalid_security_scheme_name of string
    | Conflicting_security_scheme of string
    | Invalid_security_scope of
        { scheme : string
        ; scope : string
        }

  let to_string = function
    | Duplicate_route { meth; path } -> "duplicate route: " ^ meth ^ " " ^ path
    | Ambiguous_route { meth; path; conflicts_with } ->
      "ambiguous route: " ^ meth ^ " " ^ path ^ " conflicts with " ^ conflicts_with
    | Invalid_group_prefix_segment segment -> "invalid group prefix segment: " ^ segment
    | Invalid_route_path { meth; path } ->
      "invalid typed route path: " ^ meth ^ " " ^ path
    | Mismatched_path_parameters { meth; path; declared; captures } ->
      let names values = "[" ^ String.concat values ~sep:", " ^ "]" in
      "path captures do not match declared parameters: "
      ^ meth
      ^ " "
      ^ path
      ^ "; declared "
      ^ names declared
      ^ ", captures "
      ^ names captures
    | Duplicate_operation_id operation_id -> "duplicate operationId: " ^ operation_id
    | Duplicate_parameter { meth; path; kind; name } ->
      let source =
        match kind with
        | `Path -> "path"
        | `Query -> "query"
        | `Header -> "header"
      in
      "duplicate " ^ source ^ " parameter " ^ name ^ ": " ^ meth ^ " " ^ path
    | Duplicate_response_status { meth; path; status } ->
      "duplicate response status " ^ Int.to_string status ^ ": " ^ meth ^ " " ^ path
    | Invalid_response_status { meth; path; status } ->
      "invalid response status " ^ Int.to_string status ^ ": " ^ meth ^ " " ^ path
    | Invalid_no_content_response { meth; path } ->
      "204 response must use an empty payload: " ^ meth ^ " " ^ path
    | Invalid_body_limit { meth; path; max_body_bytes } ->
      "invalid body limit " ^ Int.to_string max_body_bytes ^ ": " ^ meth ^ " " ^ path
    | Invalid_header_name { meth; path; name } ->
      "invalid header name " ^ name ^ ": " ^ meth ^ " " ^ path
    | Duplicate_response_header { meth; path; status; name } ->
      "duplicate response header "
      ^ name
      ^ " for status "
      ^ Int.to_string status
      ^ ": "
      ^ meth
      ^ " "
      ^ path
    | Conflicting_response_header { meth; path; status; name } ->
      "conflicting response header "
      ^ name
      ^ " for status "
      ^ Int.to_string status
      ^ ": "
      ^ meth
      ^ " "
      ^ path
    | Invalid_schema_name name -> "invalid OpenAPI schema name: " ^ name
    | Conflicting_schema name -> "conflicting OpenAPI schema: " ^ name
    | Invalid_security_scheme_name name -> "invalid security scheme name: " ^ name
    | Conflicting_security_scheme name -> "conflicting security scheme: " ^ name
    | Invalid_security_scope { scheme; scope } ->
      "invalid security scope " ^ scope ^ " for scheme " ^ scheme
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

  type t =
    { groups : compiled_group list
    ; schemas : Schema.t list
    ; security_schemes : Security.Scheme.t list
    }

  let groups t = t.groups
  let schemas t = t.schemas
  let security_schemes t = t.security_schemes
end

let prefix_to_string = function
  | [] -> ""
  | segments -> "/" ^ String.concat ~sep:"/" segments
;;

let full_path ~prefix path =
  if String.is_empty prefix then
    path
  else if String.equal path "/" then
    prefix
  else
    prefix ^ path
;;

let valid_group_prefix_segment segment =
  (not (String.is_empty segment))
  && (not (String.mem segment '/'))
  && (not (String.is_prefix segment ~prefix:":"))
  && (not (String.is_prefix segment ~prefix:"*"))
  && (not (String.equal segment "."))
  && not (String.equal segment "..")
;;

let valid_typed_route_path path =
  if String.equal path "/" then
    true
  else if not (String.is_prefix path ~prefix:"/") then
    false
  else
    String.drop_prefix path 1
    |> String.split ~on:'/'
    |> List.for_all ~f:(fun segment ->
      (not (String.is_empty segment))
      && (not (String.is_prefix segment ~prefix:"*"))
      && (not (String.equal segment "."))
      && (not (String.equal segment ".."))
      &&
      if String.is_prefix segment ~prefix:":" then
        String.length segment > 1
      else
        true)
;;

let path_captures path =
  String.split path ~on:'/'
  |> List.filter_map ~f:(fun segment -> String.chop_prefix segment ~prefix:":")
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

let duplicate_parameters params =
  let seen = Hash_set.create (module String) in
  List.filter params ~f:(fun param ->
    let kind, name =
      match param.kind with
      | `Path -> "path", param.name
      | `Query -> "query", param.name
      | `Header -> "header", String.lowercase param.name
    in
    let key = kind ^ "\000" ^ name in
    if Hash_set.mem seen key then
      true
    else (
      Hash_set.add seen key;
      false))
;;

let route_shape path =
  String.split path ~on:'/'
  |> List.map ~f:(fun segment ->
    if String.is_prefix segment ~prefix:":" then
      ":"
    else
      segment)
  |> String.concat ~sep:"/"
;;

let valid_http_status status = status >= 100 && status <= 599

let valid_header_name name =
  (not (String.is_empty name))
  && String.for_all name ~f:(fun char ->
    Char.is_alphanum char || String.mem "!#$%&'*+-.^_`|~" char)
;;

let response_header_equal left right =
  String.Caseless.equal left.name right.name
  && Bool.equal left.required right.required
  && Schema.equal left.schema right.schema
  && Poly.equal left.metadata right.metadata
;;

let duplicate_response_headers headers =
  let seen = Hash_set.create (module String) in
  List.filter headers ~f:(fun header ->
    let name = String.lowercase header.name in
    if Hash_set.mem seen name then
      true
    else (
      Hash_set.add seen name;
      false))
;;

let deduplicate_schemas schemas =
  List.fold schemas ~init:[] ~f:(fun unique schema ->
    if List.exists unique ~f:(Schema.equal schema) then
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
    List.concat_map contents ~f:(function
      | Text -> []
      | Json schemas -> schemas)
    |> deduplicate_schemas
  in
  let json_content =
    if List.is_empty schemas then
      []
    else
      [ Json schemas ]
  in
  let headers =
    List.fold secondary.headers ~init:primary.headers ~f:(fun headers header ->
      if List.exists headers ~f:(fun existing -> response_header_equal existing header)
      then
        headers
      else
        headers @ [ header ])
  in
  { primary with
    headers
  ; content =
      (if has_text then
         [ Text ]
       else
         [])
      @ json_content
  }
;;

let add_response responses additional =
  if
    List.exists responses ~f:(fun response -> Int.equal response.status additional.status)
  then
    List.map responses ~f:(fun response ->
      if Int.equal response.status additional.status then
        { response with payload = merge_payloads response.payload additional.payload }
      else
        response)
  else
    responses @ [ additional ]
;;

let add_implicit_responses (endpoint : endpoint) =
  let responses =
    List.fold
      (endpoint.decode_error_responses @ endpoint.context_responses)
      ~init:endpoint.responses
      ~f:add_response
  in
  { endpoint with responses; decode_error_responses = []; context_responses = [] }
;;

let valid_component_name name =
  (not (String.is_empty name))
  && String.for_all name ~f:(fun char ->
    Char.is_alphanum char
    || Char.equal char '.'
    || Char.equal char '_'
    || Char.equal char '-')
;;

let schemas_of_endpoint (endpoint : endpoint) =
  let params = List.map endpoint.params ~f:(fun param -> param.schema) in
  let request =
    match endpoint.request_body with
    | No_body | Text_body _ | Binary_body _ -> []
    | Json_body { schema; _ } -> [ schema ]
  in
  let responses =
    List.concat_map endpoint.responses ~f:(fun response ->
      List.map response.payload.headers ~f:(fun header -> header.schema)
      @ List.concat_map response.payload.content ~f:(function
        | Text -> []
        | Json schemas -> schemas))
  in
  params @ request @ responses
;;

let body_limit = function
  | No_body -> None
  | Json_body { max_body_bytes; _ }
  | Text_body { max_body_bytes; _ }
  | Binary_body { max_body_bytes; _ } -> Some max_body_bytes
;;

let validate_security_scope scheme scope =
  match scheme.Security.Scheme.kind with
  | Oauth2_implicit { scopes; _ } ->
    List.exists scopes ~f:(fun (declared, _description) -> String.equal declared scope)
  | Api_key _ | Http_bearer _ -> false
;;

let compile (groups : group list) : (Compiled.t, Compile_error.t list) Result.t =
  let routes_seen = Hashtbl.create (module String) in
  let operation_ids = Hash_set.create (module String) in
  let named_schemas = Hashtbl.create (module String) in
  let security_schemes = Hashtbl.create (module String) in
  let errors = ref [] in
  let add_error error = errors := error :: !errors in
  let register_schema schema =
    Option.iter schema.Schema.name ~f:(fun name ->
      if not (valid_component_name name) then
        add_error (Compile_error.Invalid_schema_name name)
      else (
        match
          Hashtbl.find named_schemas name
        with
        | None -> Hashtbl.set named_schemas ~key:name ~data:schema
        | Some existing ->
          if not (Schema.equal existing schema) then
            add_error (Compile_error.Conflicting_schema name)))
  in
  let register_scheme scheme =
    let name = scheme.Security.Scheme.name in
    if not (valid_component_name name) then
      add_error (Compile_error.Invalid_security_scheme_name name)
    else (
      match
        Hashtbl.find security_schemes name
      with
      | None -> Hashtbl.set security_schemes ~key:name ~data:scheme
      | Some existing ->
        if not (Security.Scheme.equal existing scheme) then
          add_error (Compile_error.Conflicting_security_scheme name))
  in
  let compiled_groups =
    List.map groups ~f:(fun group ->
      let prefix_is_valid = List.for_all group.prefix ~f:valid_group_prefix_segment in
      List.filter group.prefix ~f:(Fn.non valid_group_prefix_segment)
      |> List.iter ~f:(fun segment ->
        add_error (Compile_error.Invalid_group_prefix_segment segment));
      let prefix = prefix_to_string group.prefix in
      let routes =
        List.map group.routes ~f:(fun route ->
          let path = full_path ~prefix route.path in
          let route_key = route.meth ^ " " ^ route_shape path in
          (match Hashtbl.find routes_seen route_key with
           | None -> Hashtbl.set routes_seen ~key:route_key ~data:path
           | Some first_path when String.equal first_path path ->
             add_error (Compile_error.Duplicate_route { meth = route.meth; path })
           | Some conflicts_with ->
             add_error
               (Compile_error.Ambiguous_route { meth = route.meth; path; conflicts_with }));
          let endpoint =
            Option.map route.endpoint ~f:(fun endpoint ->
              let route_path_is_valid = valid_typed_route_path route.path in
              if not route_path_is_valid then
                add_error (Compile_error.Invalid_route_path { meth = route.meth; path });
              if prefix_is_valid && route_path_is_valid then (
                let declared =
                  List.filter_map endpoint.params ~f:(fun parameter ->
                    match parameter.kind with
                    | `Path -> Some parameter.name
                    | `Query | `Header -> None)
                in
                let captures = path_captures path in
                if not (List.equal String.equal declared captures) then
                  add_error
                    (Compile_error.Mismatched_path_parameters
                       { meth = route.meth; path; declared; captures }));
              Option.iter endpoint.metadata ~f:(fun metadata ->
                Option.iter metadata.operation_id ~f:(fun operation_id ->
                  if Hash_set.mem operation_ids operation_id then
                    add_error (Compile_error.Duplicate_operation_id operation_id)
                  else
                    Hash_set.add operation_ids operation_id));
              Option.iter (body_limit endpoint.request_body) ~f:(fun max_body_bytes ->
                if max_body_bytes <= 0 then
                  add_error
                    (Compile_error.Invalid_body_limit
                       { meth = route.meth; path; max_body_bytes }));
              let statuses =
                List.map endpoint.responses ~f:(fun response -> response.status)
              in
              duplicate_parameters endpoint.params
              |> List.iter ~f:(fun parameter ->
                add_error
                  (Compile_error.Duplicate_parameter
                     { meth = route.meth
                     ; path
                     ; kind = parameter.kind
                     ; name = parameter.name
                     }));
              List.iter endpoint.params ~f:(fun parameter ->
                match parameter.kind with
                | `Header when not (valid_header_name parameter.name) ->
                  add_error
                    (Compile_error.Invalid_header_name
                       { meth = route.meth; path; name = parameter.name })
                | `Path | `Query | `Header -> ());
              let declared_responses =
                endpoint.responses @ endpoint.decode_error_responses
                @ endpoint.context_responses
              in
              let duplicate_response_header_keys = Hash_set.create (module String) in
              List.iter declared_responses ~f:(fun response ->
                List.iter response.payload.headers ~f:(fun header ->
                  if not (valid_header_name header.name) then
                    add_error
                      (Compile_error.Invalid_header_name
                         { meth = route.meth; path; name = header.name }));
                duplicate_response_headers response.payload.headers
                |> List.iter ~f:(fun header ->
                  Hash_set.add
                    duplicate_response_header_keys
                    (Int.to_string response.status ^ "\000" ^ String.lowercase header.name);
                  add_error
                    (Compile_error.Duplicate_response_header
                       { meth = route.meth
                       ; path
                       ; status = response.status
                       ; name = header.name
                       })));
              List.iter endpoint.responses ~f:(fun response ->
                if not (valid_http_status response.status) then
                  add_error
                    (Compile_error.Invalid_response_status
                       { meth = route.meth; path; status = response.status });
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
                     { meth = route.meth; path; status }));
              let endpoint = add_implicit_responses endpoint in
              List.iter endpoint.responses ~f:(fun response ->
                duplicate_response_headers response.payload.headers
                |> List.iter ~f:(fun header ->
                  let key =
                    Int.to_string response.status ^ "\000" ^ String.lowercase header.name
                  in
                  if not (Hash_set.mem duplicate_response_header_keys key) then
                    add_error
                      (Compile_error.Conflicting_response_header
                         { meth = route.meth
                         ; path
                         ; status = response.status
                         ; name = header.name
                         })));
              List.iter (schemas_of_endpoint endpoint) ~f:register_schema;
              List.iter endpoint.security ~f:(fun requirement ->
                List.iter requirement ~f:(fun (scheme, scopes) ->
                  register_scheme scheme;
                  List.iter scopes ~f:(fun scope ->
                    if not (validate_security_scope scheme scope) then
                      add_error
                        (Compile_error.Invalid_security_scope
                           { scheme = scheme.name; scope }))));
              endpoint)
          in
          { Compiled.meth = route.meth; path; endpoint })
      in
      { Compiled.metadata = group.metadata; routes })
  in
  match List.rev !errors with
  | [] ->
    let schemas =
      Hashtbl.data named_schemas
      |> List.sort ~compare:(fun left right ->
        Option.compare String.compare left.Schema.name right.Schema.name)
    in
    let security_schemes =
      Hashtbl.data security_schemes
      |> List.sort ~compare:(fun left right ->
        String.compare left.Security.Scheme.name right.Security.Scheme.name)
    in
    Ok { Compiled.groups = compiled_groups; schemas; security_schemes }
  | errors -> Error errors
;;

let compile_exn groups =
  match compile groups with
  | Ok compiled -> compiled
  | Error errors ->
    errors |> List.map ~f:Compile_error.to_string |> String.concat ~sep:"; " |> failwith
;;
