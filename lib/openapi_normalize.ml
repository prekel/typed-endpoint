open! Base

let fields = function
  | `Assoc fields -> fields
  | _ -> []
;;

let member json name = List.Assoc.find (fields json) name ~equal:String.equal

let map_field json name ~f =
  match json with
  | `Assoc fields ->
    `Assoc
      (List.map fields ~f:(fun (key, value) ->
         ( key
         , if String.equal key name then
             f value
           else
             value )))
  | _ -> json
;;

let map_object json ~f =
  match json with
  | `Assoc fields -> `Assoc (List.map fields ~f:(fun (name, value) -> name, f name value))
  | _ -> json
;;

let map_field_with name f json = map_field json name ~f

let map_list json ~f =
  match json with
  | `List values -> `List (List.map values ~f)
  | _ -> json
;;

let rec ordered = function
  | `Assoc fields ->
    `Assoc
      (List.map fields ~f:(fun (name, value) -> name, ordered value)
       |> List.sort ~compare:(fun (left, _) (right, _) -> String.compare left right))
  | `List values -> `List (List.map values ~f:ordered)
  | value -> value
;;

let key json = Yojson.Safe.to_string (ordered json)
let schema_maps = [ "properties"; "patternProperties"; "dependentSchemas" ]
let schema_lists = [ "allOf"; "anyOf"; "oneOf"; "prefixItems" ]

let schema_values =
  [ "items"
  ; "contains"
  ; "additionalProperties"
  ; "unevaluatedProperties"
  ; "unevaluatedItems"
  ; "propertyNames"
  ; "not"
  ; "if"
  ; "then"
  ; "else"
  ; "contentSchema"
  ]
;;

let annotations =
  [ "type"
  ; "enum"
  ; "const"
  ; "required"
  ; "title"
  ; "description"
  ; "default"
  ; "examples"
  ; "example"
  ; "deprecated"
  ; "readOnly"
  ; "writeOnly"
  ; "$comment"
  ; "format"
  ; "minimum"
  ; "maximum"
  ; "exclusiveMinimum"
  ; "exclusiveMaximum"
  ; "multipleOf"
  ; "minLength"
  ; "maxLength"
  ; "pattern"
  ; "minItems"
  ; "maxItems"
  ; "uniqueItems"
  ; "minContains"
  ; "maxContains"
  ; "minProperties"
  ; "maxProperties"
  ; "dependentRequired"
  ; "contentEncoding"
  ; "contentMediaType"
  ; "discriminator"
  ; "xml"
  ; "externalDocs"
  ]
;;

let ordinary schema =
  List.for_all (fields schema) ~f:(fun (name, _) ->
    List.mem
      (annotations @ schema_maps @ schema_lists @ schema_values)
      name
      ~equal:String.equal)
;;

let children schema ~f =
  map_object schema ~f:(fun name value ->
    if List.mem schema_maps name ~equal:String.equal then
      map_object value ~f:(fun _ schema -> f schema)
    else if List.mem schema_lists name ~equal:String.equal then
      map_list value ~f
    else if List.mem schema_values name ~equal:String.equal then
      f value
    else
      value)
;;

let rec reusable schema =
  ordinary schema
  && List.for_all (fields schema) ~f:(fun (name, value) ->
    if List.mem schema_maps name ~equal:String.equal then
      List.for_all (fields value) ~f:(fun (_, schema) -> reusable schema)
    else if List.mem schema_lists name ~equal:String.equal then (
      match
        value
      with
      | `List values -> List.for_all values ~f:reusable
      | _ -> false)
    else if List.mem schema_values name ~equal:String.equal then
      reusable value
    else
      true)
;;

let rec clean schema =
  if not (ordinary schema) then
    schema
  else (
    match
      children schema ~f:clean
    with
    | `Assoc fields ->
      `Assoc
        (List.filter fields ~f:(function
           | "required", `List [] -> false
           | _ -> true))
    | schema -> schema)
;;

let set_field json name value =
  `Assoc
    (List.filter (fields json) ~f:(fun (key, _) -> not (String.equal key name))
     @ [ name, value ])
;;

let is_method name =
  List.mem
    [ "get"; "put"; "post"; "delete"; "patch"; "head"; "options"; "trace" ]
    name
    ~equal:String.equal
;;

let map_operations document ~f =
  map_field document "paths" ~f:(fun paths ->
    map_object paths ~f:(fun _ path ->
      map_object path ~f:(fun name value ->
        if is_method name then
          f value
        else
          value)))
;;

let parameters json =
  match member json "parameters" with
  | Some (`List values) -> values
  | _ -> []
;;

let with_parameters json parameters =
  let rest =
    List.filter (fields json) ~f:(fun (name, _) -> not (String.equal name "parameters"))
  in
  `Assoc
    (if List.is_empty parameters then
       rest
     else
       ("parameters", `List parameters) :: rest)
;;

let same_parameter left right =
  Poly.equal (member left "name") (member right "name")
  && Poly.equal (member left "in") (member right "in")
;;

let lift_path_parameters path =
  let operations = List.filter (fields path) ~f:(fun (name, _) -> is_method name) in
  match operations with
  | [] | [ _ ] -> path
  | (_, first) :: rest ->
    let existing = parameters path in
    let common =
      List.filter (parameters first) ~f:(fun parameter ->
        Poly.equal (member parameter "in") (Some (`String "path"))
        && (not (List.exists existing ~f:(same_parameter parameter)))
        && List.for_all rest ~f:(fun (_, operation) ->
          List.exists (parameters operation) ~f:(fun other ->
            String.equal (key parameter) (key other))))
    in
    if List.is_empty common then
      path
    else (
      let path =
        map_object path ~f:(fun name value ->
          if is_method name then
            with_parameters
              value
              (List.filter (parameters value) ~f:(fun parameter ->
                 not (List.exists common ~f:(same_parameter parameter))))
          else
            value)
      in
      with_parameters path (existing @ common))
;;

let clean_operation operation =
  match member operation "description" with
  | Some (`String description)
    when String.is_empty description
         || Poly.equal (member operation "summary") (Some (`String description)) ->
    `Assoc
      (List.filter (fields operation) ~f:(fun (name, _) ->
         not (String.equal name "description")))
  | _ -> operation
;;

let object_schema schema =
  match member schema "type" with
  | Some (`String "object") -> true
  | Some (`List types) -> List.mem types (`String "object") ~equal:Poly.equal
  | _ -> false
;;

let document (document : Yojson.Safe.t) =
  let components = Option.value (member document "components") ~default:(`Assoc []) in
  let schemas = Option.value (member components "schemas") ~default:(`Assoc []) in
  let schemas = map_object schemas ~f:(fun _ schema -> clean schema) in
  let index =
    fields schemas
    |> List.sort ~compare:(fun (left, _) (right, _) -> String.compare left right)
    |> List.fold
         ~init:(Map.empty (module String))
         ~f:(fun index (name, schema) ->
           let fingerprint = key schema in
           if object_schema schema && reusable schema && not (Map.mem index fingerprint)
           then
             Map.set index ~key:fingerprint ~data:name
           else
             index)
  in
  let rec rewrite ?(replace = true) schema =
    if not (ordinary schema) then
      schema
    else (
      match
        if replace && reusable schema then
          Map.find index (key schema)
        else
          None
      with
      | Some name -> `Assoc [ "$ref", `String ("#/components/schemas/" ^ name) ]
      | None -> children schema ~f:rewrite)
  in
  let render_schema schema = rewrite (clean schema) in
  let content json =
    map_object json ~f:(fun _ media -> map_field media "schema" ~f:render_schema)
  in
  let response json =
    json
    |> map_field_with "content" content
    |> map_field_with "headers" (fun headers ->
      map_object headers ~f:(fun _ header -> map_field header "schema" ~f:render_schema))
  in
  let render_parameters parameters =
    map_list parameters ~f:(fun parameter ->
      map_field parameter "schema" ~f:render_schema)
  in
  let document =
    map_field document "paths" ~f:(fun paths ->
      map_object paths ~f:(fun _ path -> map_field path "parameters" ~f:render_parameters))
  in
  let document =
    map_operations document ~f:(fun operation ->
      clean_operation operation
      |> map_field_with "parameters" render_parameters
      |> map_field_with "requestBody" (fun body -> map_field body "content" ~f:content)
      |> map_field_with "responses" (fun responses ->
        map_object responses ~f:(fun _ payload -> response payload)))
  in
  let document =
    map_field document "paths" ~f:(fun paths ->
      map_object paths ~f:(fun _ path -> lift_path_parameters path))
  in
  let components =
    map_field components "schemas" ~f:(fun _ ->
      map_object schemas ~f:(fun _ schema -> rewrite ~replace:false schema))
  in
  if List.is_empty (fields components) then
    document
  else
    set_field document "components" components
;;
