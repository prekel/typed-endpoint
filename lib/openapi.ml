open! Base

let path_to_openapi path =
  String.split ~on:'/' path
  |> List.map ~f:(fun segment ->
    if String.is_prefix segment ~prefix:":" then
      "{" ^ String.drop_prefix segment 1 ^ "}"
    else
      segment)
  |> String.concat ~sep:"/"
;;

let yo_str value = `String value
let yo_bool value = `Bool value
let yo_list values = `List values
let yo_obj fields = `Assoc fields
let schema_ref name = yo_obj [ "$ref", yo_str ("#/components/schemas/" ^ name) ]

let render_schema (schema : Contract.Schema.t) =
  match schema.name with
  | Some name -> schema_ref name
  | None -> (schema.value :> Yojson.Safe.t)
;;

let render_param (param : Contract.param) =
  yo_obj
    [ "name", yo_str param.name
    ; ( "in"
      , yo_str
          (match param.kind with
           | `Path -> "path"
           | `Query -> "query"
           | `Header -> "header") )
    ; "required", yo_bool param.required
    ; "description", yo_str param.metadata.description
    ; "schema", render_schema param.schema
    ]
;;

let render_request_body = function
  | Contract.No_body -> None
  | Text_body { metadata; _ } ->
    Some
      (yo_obj
         [ "required", yo_bool true
         ; "description", yo_str metadata.description
         ; ( "content"
           , yo_obj
               [ "text/plain", yo_obj [ "schema", yo_obj [ "type", yo_str "string" ] ] ] )
         ])
  | Binary_body { metadata; _ } ->
    Some
      (yo_obj
         [ "required", yo_bool true
         ; "description", yo_str metadata.description
         ; ( "content"
           , yo_obj
               [ ( "application/octet-stream"
                 , yo_obj
                     [ ( "schema"
                       , yo_obj [ "type", yo_str "string"; "format", yo_str "binary" ] )
                     ] )
               ] )
         ])
  | Json_body { schema; metadata; _ } ->
    Some
      (yo_obj
         [ "required", yo_bool true
         ; "description", yo_str metadata.description
         ; ( "content"
           , yo_obj [ "application/json", yo_obj [ "schema", render_schema schema ] ] )
         ])
;;

let render_json_schemas schemas =
  match schemas with
  | [] -> yo_bool true
  | [ schema ] -> render_schema schema
  | schemas -> yo_obj [ "oneOf", yo_list (List.map schemas ~f:render_schema) ]
;;

let render_response_payload (payload : Contract.response_payload) =
  let content =
    List.filter_map payload.content ~f:(function
      | Text ->
        Some ("text/plain", yo_obj [ "schema", yo_obj [ "type", yo_str "string" ] ])
      | Json schemas ->
        Some ("application/json", yo_obj [ "schema", render_json_schemas schemas ]))
  in
  let headers =
    payload.headers
    |> List.sort ~compare:(fun (left : Contract.response_header) right ->
      String.Caseless.compare left.name right.name)
    |> List.map ~f:(fun (header : Contract.response_header) ->
      ( header.name
      , yo_obj
          [ "required", yo_bool header.required
          ; "description", yo_str header.metadata.description
          ; "schema", render_schema header.schema
          ] ))
  in
  yo_obj
    ([ "description", yo_str payload.metadata.description ]
     @ (if List.is_empty headers then
          []
        else
          [ "headers", yo_obj headers ])
     @
     if List.is_empty content then
       []
     else
       [ "content", yo_obj content ])
;;

let operation_metadata
      ~(group : Contract.Operation_metadata.t)
      (operation : Contract.Operation_metadata.t option)
  =
  match operation with
  | None -> group
  | Some operation ->
    { operation with
      tags = List.dedup_and_sort ~compare:String.compare (group.tags @ operation.tags)
    }
;;

let render_security_requirement (requirement : Contract.Security.requirement) =
  requirement
  |> List.sort ~compare:(fun (left, _) (right, _) ->
    String.compare left.Contract.Security.Scheme.name right.name)
  |> List.map ~f:(fun ((scheme : Contract.Security.Scheme.t), scopes) ->
    scheme.name, yo_list (List.map scopes ~f:yo_str))
  |> yo_obj
;;

let render_operation
      ~(group_metadata : Contract.Operation_metadata.t)
      (endpoint : Contract.endpoint)
  =
  let metadata = operation_metadata ~group:group_metadata endpoint.metadata in
  let params = yo_list (List.map endpoint.params ~f:render_param) in
  let request_body = render_request_body endpoint.request_body in
  let responses =
    endpoint.responses
    |> List.sort ~compare:(fun (left : Contract.response) right ->
      Int.compare left.status right.status)
    |> List.map ~f:(fun (response : Contract.response) ->
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
       ; (if List.is_empty endpoint.security then
            []
          else
            [ ( "security"
              , endpoint.security |> List.map ~f:render_security_requirement |> yo_list )
            ])
       ; base
       ])
;;

let render_security_scheme (scheme : Contract.Security.Scheme.t) =
  let description = [ "description", yo_str scheme.description ] in
  match scheme.kind with
  | Api_key { parameter; location } ->
    yo_obj
      ([ "type", yo_str "apiKey"
       ; "name", yo_str parameter
       ; ( "in"
         , yo_str
             (match location with
              | `Header -> "header"
              | `Query -> "query"
              | `Cookie -> "cookie") )
       ]
       @ description)
  | Http_bearer { bearer_format } ->
    yo_obj
      ([ "type", yo_str "http"; "scheme", yo_str "bearer" ]
       @ (match bearer_format with
          | None -> []
          | Some format -> [ "bearerFormat", yo_str format ])
       @ description)
  | Oauth2_implicit { authorization_url; scopes } ->
    let scopes =
      scopes
      |> List.sort ~compare:(fun (left, _) (right, _) -> String.compare left right)
      |> List.map ~f:(fun (name, description) -> name, yo_str description)
      |> yo_obj
    in
    yo_obj
      ([ "type", yo_str "oauth2"
       ; ( "flows"
         , yo_obj
             [ ( "implicit"
               , yo_obj [ "authorizationUrl", yo_str authorization_url; "scopes", scopes ]
               )
             ] )
       ]
       @ description)
;;

let render_components compiled =
  let schemas =
    Contract.Compiled.schemas compiled
    |> List.filter_map ~f:(fun schema ->
      Option.map schema.Contract.Schema.name ~f:(fun name ->
        name, (schema.value :> Yojson.Safe.t)))
  in
  let security_schemes =
    Contract.Compiled.security_schemes compiled
    |> List.map ~f:(fun (scheme : Contract.Security.Scheme.t) ->
      scheme.name, render_security_scheme scheme)
  in
  match schemas, security_schemes with
  | [], [] -> None
  | _ ->
    Some
      (yo_obj
         ((if List.is_empty schemas then
             []
           else
             [ "schemas", yo_obj schemas ])
          @
          if List.is_empty security_schemes then
            []
          else
            [ "securitySchemes", yo_obj security_schemes ]))
;;

let render_server (server : Contract.Openapi.Server.t) =
  yo_obj
    ([ "url", yo_str server.url ]
     @
     match server.description with
     | None -> []
     | Some description -> [ "description", yo_str description ])
;;

let render ~config (compiled : Contract.Compiled.t) =
  let groups = Contract.Compiled.groups compiled in
  let tags =
    groups
    |> List.concat_map ~f:(fun group ->
      List.map group.Contract.Compiled.metadata.tags ~f:(fun name ->
        name, group.metadata.description))
    |> List.sort_and_group ~compare:(fun (left, _) (right, _) ->
      String.compare left right)
    |> List.map ~f:(fun group ->
      let name, description = List.hd_exn group in
      yo_obj [ "name", yo_str name; "description", yo_str description ])
    |> yo_list
  in
  let path_entries =
    List.concat_map groups ~f:(fun group ->
      List.filter_map group.routes ~f:(fun route ->
        Option.map route.endpoint ~f:(fun endpoint ->
          ( path_to_openapi route.path
          , route.meth
          , render_operation ~group_metadata:group.metadata endpoint ))))
    |> List.sort ~compare:(fun (left_path, left_meth, _) (right_path, right_meth, _) ->
      match String.compare left_path right_path with
      | 0 -> String.compare left_meth right_meth
      | comparison -> comparison)
    |> List.group ~break:(fun (left_path, _, _) (right_path, _, _) ->
      not (String.equal left_path right_path))
    |> List.map ~f:(fun entries ->
      let path, _, _ = List.hd_exn entries in
      let methods =
        List.map entries ~f:(fun (_, meth, operation) -> meth, operation) |> yo_obj
      in
      path, methods)
    |> yo_obj
  in
  let info =
    yo_obj
      ([ "title", yo_str config.Contract.Openapi.Config.title
       ; "version", yo_str config.version
       ]
       @
       match config.description with
       | None -> []
       | Some description -> [ "description", yo_str description ])
  in
  yo_obj
    (List.concat
       [ [ "openapi", yo_str "3.1.0"; "info", info ]
       ; (if List.is_empty config.servers then
            []
          else
            [ "servers", yo_list (List.map config.servers ~f:render_server) ])
       ; [ "tags", tags; "paths", path_entries ]
       ; (match render_components compiled with
          | None -> []
          | Some components -> [ "components", components ])
       ])
;;
