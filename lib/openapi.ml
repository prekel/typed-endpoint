open! Base

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

let yo_str value = `String value
let yo_bool value = `Bool value
let yo_list values = `List values
let yo_obj fields = `Assoc fields

let yo_schema (schema : Ppx_deriving_jsonschema_runtime.t) : Yojson.Safe.t =
  (schema :> Yojson.Safe.t)
;;

let render_param (param : Contract.param) : Yojson.Safe.t =
  yo_obj
    [ "name", yo_str param.name
    ; ( "in"
      , yo_str
          (match param.kind with
           | `Path -> "path"
           | `Query -> "query") )
    ; "required", yo_bool param.required
    ; "description", yo_str param.metadata.description
    ; "schema", yo_schema param.schema
    ]
;;

let render_request_body (request_body : Contract.request_body) : Yojson.Safe.t option =
  match request_body with
  | No_body -> None
  | Text_body { metadata } ->
    Some
      (yo_obj
         [ "required", yo_bool true
         ; "description", yo_str metadata.description
         ; ( "content"
           , yo_obj
               [ "text/plain", yo_obj [ "schema", yo_obj [ "type", yo_str "string" ] ] ] )
         ])
  | Json_body { schema; metadata } ->
    Some
      (yo_obj
         [ "required", yo_bool true
         ; "description", yo_str metadata.description
         ; "content", yo_obj [ "application/json", yo_obj [ "schema", yo_schema schema ] ]
         ])
;;

let render_response_payload (payload : Contract.response_payload) : Yojson.Safe.t =
  let content =
    List.filter_map payload.content ~f:(function
      | Text ->
        Some ("text/plain", yo_obj [ "schema", yo_obj [ "type", yo_str "string" ] ])
      | Json schema -> Some ("application/json", yo_obj [ "schema", yo_schema schema ]))
  in
  yo_obj
    ([ "description", yo_str payload.metadata.description ]
     @
     if List.is_empty content then
       []
     else
       [ "content", yo_obj content ])
;;

let operation_metadata
      ~(group : Contract.Metadata.t)
      (operation : Contract.Metadata.t option)
  =
  match operation with
  | None -> group
  | Some operation ->
    { operation with
      tags = List.dedup_and_sort ~compare:String.compare (group.tags @ operation.tags)
    }
;;

let render_operation
      ~(group_metadata : Contract.Metadata.t)
      (endpoint : Contract.endpoint)
  : Yojson.Safe.t
  =
  let metadata = operation_metadata ~group:group_metadata endpoint.metadata in
  let params = yo_list (List.map endpoint.params ~f:render_param) in
  let request_body = render_request_body endpoint.request_body in
  let responses =
    endpoint.responses
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
       ; base
       ])
;;

let render ?(title = "API") ?(version = "0.1.0") (compiled : Contract.Compiled.t)
  : Yojson.Safe.t
  =
  let groups = Contract.Compiled.groups compiled in
  let tags =
    groups
    |> List.concat_map ~f:(fun (group : Contract.Compiled.compiled_group) ->
      List.map group.metadata.tags ~f:(fun name ->
        yo_obj [ "name", yo_str name; "description", yo_str group.metadata.description ]))
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
  List.iter groups ~f:(fun (group : Contract.Compiled.compiled_group) ->
    List.iter group.routes ~f:(fun (route : Contract.Compiled.compiled_route) ->
      Option.iter route.endpoint ~f:(fun endpoint ->
        let path = path_to_openapi route.path in
        let operation = render_operation ~group_metadata:group.metadata endpoint in
        Hashtbl.update by_path path ~f:(function
          | None -> Map.singleton (module String) route.meth operation
          | Some methods -> Map.set methods ~key:route.meth ~data:operation))));
  let paths =
    Hashtbl.to_alist by_path
    |> List.map ~f:(fun (path, methods) -> path, Map.to_alist methods |> yo_obj)
    |> yo_obj
  in
  yo_obj
    [ "openapi", yo_str "3.1.0"
    ; "info", yo_obj [ "title", yo_str title; "version", yo_str version ]
    ; "tags", tags
    ; "paths", paths
    ]
;;
