open! Base
module Check = Contract_test_support

let member = Yojson.Safe.Util.member
let fields = Yojson.Safe.Util.to_assoc

let rec canonical = function
  | `Assoc values ->
    `Assoc
      (List.map values ~f:(fun (k, v) -> k, canonical v)
       |> List.sort ~compare:(fun (a, _) (b, _) -> String.compare a b))
  | `List values -> `List (List.map values ~f:canonical)
  | value -> value
;;

let equal a b = Yojson.Safe.equal (canonical a) (canonical b)
let map_fields json f = `Assoc (List.map (fields json) ~f)

let set json name value =
  `Assoc
    ((name, value)
     :: List.filter (fields json) ~f:(fun (key, _) -> not (String.equal key name)))
;;

let response description schema =
  `Assoc
    [ "description", `String description
    ; "content", `Assoc [ "application/json", `Assoc [ "schema", schema ] ]
    ]
;;

let document schemas responses =
  `Assoc
    [ "openapi", `String "3.1.0"
    ; "info", `Assoc [ "title", `String "Conformance"; "version", `String "1" ]
    ; "components", `Assoc [ "schemas", `Assoc schemas ]
    ; ( "paths"
      , `Assoc
          (List.map responses ~f:(fun (path, response) ->
             path, `Assoc [ "get", `Assoc [ "responses", `Assoc [ "200", response ] ] ]))
      )
    ]
;;

let payload doc path =
  doc
  |> member "paths"
  |> member path
  |> member "get"
  |> member "responses"
  |> member "200"
;;

let response_schema doc path =
  Check.resolve_response_exn doc (payload doc path)
  |> member "content"
  |> member "application/json"
  |> member "schema"
;;

(* This oracle understands only the pure component references introduced by the
   normalizer. Imported resource scopes and schema applicators stay intact. *)
let projection doc =
  let rec schema seen json =
    match json with
    | `Assoc [ ("$ref", `String reference) ]
      when String.is_prefix reference ~prefix:"#/components/schemas/" ->
      assert (not (List.mem seen reference ~equal:String.equal));
      let name = String.chop_prefix_exn reference ~prefix:"#/components/schemas/" in
      doc
      |> member "components"
      |> member "schemas"
      |> member name
      |> schema (reference :: seen)
    | `Assoc values
      when List.exists values ~f:(fun (name, _) ->
             List.mem [ "$id"; "$defs"; "$ref" ] name ~equal:String.equal) -> json
    | `Assoc values ->
      `Assoc
        (List.filter_map values ~f:(fun (name, value) ->
           if String.equal name "required" && equal value (`List []) then
             None
           else
             Some
               ( name
               , match name, value with
                 | "properties", `Assoc properties ->
                   `Assoc (List.map properties ~f:(fun (k, v) -> k, schema seen v))
                 | ("items" | "additionalProperties"), value -> schema seen value
                 | ("allOf" | "anyOf" | "oneOf" | "prefixItems"), `List values ->
                   `List (List.map values ~f:(schema seen))
                 | _ -> value )))
    | value -> value
  in
  let content json =
    map_fields json (fun (media, definition) ->
      ( media
      , map_fields definition (fun (name, value) ->
          ( name
          , if String.equal name "schema" then
              schema [] value
            else
              value )) ))
  in
  let response json =
    Check.resolve_response_exn doc json |> fun json ->
    map_fields json (fun (name, value) ->
      ( name
      , match name with
        | "content" -> content value
        | "headers" ->
          map_fields value (fun (name, header) ->
            ( name
            , map_fields header (fun (k, v) ->
                ( k
                , if String.equal k "schema" then
                    schema [] v
                  else
                    v )) ))
        | _ -> value ))
  in
  let paths =
    doc |> member "paths" |> fun paths ->
    map_fields paths (fun (path, item) ->
      let operations =
        fields item
        |> List.filter ~f:(fun (meth, _) ->
          List.mem
            [ "get"; "post"; "put"; "delete"; "patch"; "head"; "options"; "trace" ]
            meth
            ~equal:String.equal)
      in
      ( path
      , `Assoc
          (List.map operations ~f:(fun (meth, _) ->
             let operation = Check.operation_exn doc ~path ~meth in
             let operation =
               `Assoc
                 (List.filter (fields operation) ~f:(fun (name, value) ->
                    not
                      (String.equal name "description"
                       && (equal value (`String "")
                           || equal value (member "summary" operation)))))
             in
             ( meth
             , map_fields operation (fun (name, value) ->
                 ( name
                 , match name, value with
                   | "responses", value ->
                     map_fields value (fun (status, r) -> status, response r)
                   | "parameters", `List parameters ->
                     `List
                       (List.map parameters ~f:(fun parameter ->
                          map_fields parameter (fun (name, value) ->
                            ( name
                            , if String.equal name "schema" then
                                schema [] value
                              else
                                value ))))
                   | "requestBody", value ->
                     map_fields value (fun (name, value) ->
                       ( name
                       , if String.equal name "content" then
                           content value
                         else
                           value ))
                   | _ -> value )) ))) ))
  in
  `Assoc
    [ "paths", paths
    ; ( "schemas"
      , match member "components" doc with
        | `Assoc components ->
          (match List.Assoc.find components "schemas" ~equal:String.equal with
           | Some (`Assoc _ as schemas) ->
             map_fields schemas (fun (name, value) -> name, schema [] value)
           | _ -> `Assoc [])
        | _ -> `Assoc [] )
    ]
;;

let schema minimum maximum =
  `Assoc
    [ "type", `String "object"
    ; ( "properties"
      , `Assoc
          [ ( "n"
            , `Assoc
                [ "type", `String "integer"
                ; "minimum", `Int minimum
                ; "maximum", `Int maximum
                ] )
          ; "unused", `Assoc [ "type", `String "object"; "required", `List [] ]
          ] )
    ; "required", `List [ `String "n" ]
    ; "additionalProperties", `Bool false
    ; "default", `Assoc [ "required", `List []; "$ref", `String "literal" ]
    ; "examples", `List [ `Assoc [ "required", `List [] ] ]
    ]
;;

let normalization =
  QCheck2.Test.make
    ~name:"normalization: restored operations and schema acceptance are preserved"
    ~count:150
    QCheck2.Gen.(triple (int_range (-50) 50) (int_range 0 50) bool)
    (fun (minimum, width, reverse) ->
       let maximum = minimum + width in
       let item = schema minimum maximum in
       let array = `Assoc [ "type", `String "array"; "items", item ] in
       let responses =
         [ "/one/{id}", response "First" item
         ; "/two/{id}", response "" item
         ; "/array/{id}", response "Items" array
         ]
       in
       let responses =
         if reverse then
           List.rev responses
         else
           responses
       in
       let number = item |> member "properties" |> member "n" in
       let make responses =
         let doc = document [ "Item", item; "Number", number ] responses in
         let paths =
           member "paths" doc |> fun paths ->
           map_fields paths (fun (path, entry) ->
             ( path
             , map_fields entry (fun (meth, operation) ->
                 ( meth
                 , operation |> fun operation ->
                   set
                     operation
                     "parameters"
                     (`List
                         [ `Assoc
                             [ "name", `String "id"
                             ; "in", `String "path"
                             ; "required", `Bool true
                             ; "schema", number
                             ]
                         ; `Assoc
                             [ "name", `String "n"
                             ; "in", `String "query"
                             ; "schema", number
                             ]
                         ])
                   |> fun operation ->
                   set
                     operation
                     "requestBody"
                     (`Assoc
                         [ ( "content"
                           , `Assoc [ "application/json", `Assoc [ "schema", item ] ] )
                         ]) )) ))
         in
         let paths =
           map_fields paths (fun (path, entry) ->
             let get =
               member "get" entry |> fun operation ->
               set
                 (set operation "summary" (`String "Fetch"))
                 "description"
                 (`String "Fetch")
             in
             let post =
               member "get" entry |> fun operation ->
               set
                 (set operation "summary" (`String "Replace"))
                 "description"
                 (`String "Replaces the item")
             in
             path, `Assoc [ "get", get; "post", post ])
         in
         set doc "paths" paths
       in
       let original = make responses in
       let normalized = Openapi_normalize.document original in
       let values =
         [ `Assoc [ "n", `Int minimum ]
         ; `Assoc [ "n", `Int maximum ]
         ; `Assoc [ "n", `Int (minimum - 1) ]
         ; `Assoc [ "n", `Int (maximum + 1) ]
         ; `Assoc []
         ; `Assoc [ "n", `String "wrong" ]
         ; `Null
         ; `Assoc [ "n", `Int minimum; "extra", `Bool true ]
         ]
       in
       let acceptance schema_of values =
         List.for_all
           (List.mapi values ~f:(fun index value -> index, value))
           ~f:(fun (index, value) ->
             let valid doc =
               Result.is_ok (Check.validate ~document:doc ~schema:(schema_of doc) value)
             in
             Bool.equal (valid original) (index < 2)
             && Bool.equal (valid original) (valid normalized))
       in
       equal (projection original) (projection normalized)
       && equal normalized (Openapi_normalize.document normalized)
       && equal normalized (Openapi_normalize.document (make (List.rev responses)))
       && acceptance (fun doc -> response_schema doc "/one/{id}") values
       && acceptance
            (fun doc -> response_schema doc "/array/{id}")
            (List.map values ~f:(fun value -> `List [ value ]))
       && acceptance
            (fun doc ->
               doc
               |> member "paths"
               |> member "/one/{id}"
               |> member "get"
               |> member "requestBody"
               |> member "content"
               |> member "application/json"
               |> member "schema")
            values
       && acceptance
            (fun doc ->
               doc
               |> member "paths"
               |> member "/one/{id}"
               |> member "get"
               |> member "parameters"
               |> Yojson.Safe.Util.to_list
               |> List.hd_exn
               |> member "schema")
            [ `Int minimum; `Int maximum; `Int (minimum - 1); `Int (maximum + 1); `Null ])
;;

let () =
  let plain = `Assoc [ "type", `String "integer" ] in
  let base = document [] [ "/one", response "Found" plain; "/two", response "" plain ] in
  let normalized = Openapi_normalize.document base in
  assert (equal (payload normalized "/one") (payload base "/one"));
  assert (equal (payload normalized "/two") (payload base "/two"));
  assert (equal (normalized |> member "components" |> member "responses") `Null);
  assert (equal (projection base) (projection normalized));
  (* Existing reference objects are imported fixtures; the renderer never
     creates them. Their annotations and components must remain untouched. *)
  let retained = response "Existing" (`Assoc [ "type", `String "string" ]) in
  let components =
    member "components" base |> fun c ->
    set c "responses" (`Assoc [ "Existing", retained ])
  in
  let reference = `Assoc [ "$ref", `String "#/components/responses/Existing" ] in
  let imported =
    document [] [ "/ref", reference; "/empty", set reference "description" (`String "") ]
    |> fun doc -> set doc "components" components
  in
  let after = Openapi_normalize.document imported in
  assert (equal imported after);
  assert (
    equal
      (Check.resolve_response_exn after (payload after "/ref") |> member "description")
      (`String "Existing"));
  assert (
    equal
      (Check.resolve_response_exn after (payload after "/empty") |> member "description")
      (`String ""))
;;

let () =
  let plain = `Assoc [ "type", `String "string" ] in
  let original = response "Same" plain in
  let different =
    [ "/plain", original
    ; "/headers", set original "headers" (`Assoc [ "x-mode", `Assoc [ "schema", plain ] ])
    ; ( "/links"
      , set original "links" (`Assoc [ "next", `Assoc [ "operationId", `String "next" ] ])
      )
    ; "/schema", response "Same" (set plain "description" (`String "Different schema"))
    ; ( "/media"
      , `Assoc
          [ "description", `String "Same"
          ; "content", `Assoc [ "text/plain", `Assoc [ "schema", plain ] ]
          ] )
    ]
  in
  let doc = document [] different |> Openapi_normalize.document in
  List.iter different ~f:(fun (path, _) ->
    assert (equal (member "$ref" (payload doc path)) `Null))
;;

let () =
  let resource =
    Yojson.Safe.from_string
      {|{
    "$id":"urn:typed-endpoint:conformance:node",
    "$defs":{"node":{"type":"object","properties":{"value":{"type":"integer"},"next":{"anyOf":[{"type":"null"},{"$ref":"#/$defs/node"}]}},"required":["value"],"additionalProperties":false}},
    "$ref":"#/$defs/node"
  }|}
  in
  let number = `Assoc [ "type", `String "integer"; "maximum", `Int 10 ] in
  let sibling =
    `Assoc [ "$ref", `String "#/components/schemas/Number"; "minimum", `Int 1 ]
  in
  let unknown =
    `Assoc
      [ "type", `String "object"; "x-private-keyword", `Bool true; "required", `List [] ]
  in
  let original =
    document
      [ "Node", resource; "Number", number; "Unknown", unknown ]
      [ "/resource", response "Node" resource; "/sibling", response "Number" sibling ]
  in
  let normalized = Openapi_normalize.document original in
  assert (equal (projection original) (projection normalized));
  List.iter
    [ "Node", resource; "Unknown", unknown ]
    ~f:(fun (name, value) ->
      assert (
        equal (normalized |> member "components" |> member "schemas" |> member name) value));
  assert (
    Result.is_error
      (Check.validate
         ~document:original
         ~schema:(response_schema original "/resource")
         (`Assoc [ "value", `Int 1 ])));
  (* The validator cannot resolve embedded resource scopes. Check their exact
     preservation above, and validate recursion with each resource as its root. *)
  List.iteri
    [ `Assoc [ "value", `Int 1 ]
    ; `Assoc [ "value", `Int 1; "next", `Assoc [ "value", `Int 2 ] ]
    ; `Assoc [ "value", `String "wrong" ]
    ; `Assoc [ "next", `Null ]
    ]
    ~f:(fun index value ->
      let valid doc =
        let resource = doc |> member "components" |> member "schemas" |> member "Node" in
        Result.is_ok (Check.validate ~document:resource ~schema:resource value)
      in
      assert (Bool.equal (valid original) (index < 2));
      assert (Bool.equal (valid original) (valid normalized)));
  List.iter [ 0; 1; 10; 11 ] ~f:(fun n ->
    let valid doc =
      Result.is_ok
        (Check.validate ~document:doc ~schema:(response_schema doc "/sibling") (`Int n))
    in
    assert (Bool.equal (valid original) (n >= 1 && n <= 10));
    assert (Bool.equal (valid original) (valid normalized)))
;;

let () =
  let parameter =
    `Assoc
      [ "name", `String "id"
      ; "in", `String "path"
      ; "required", `Bool true
      ; "description", `String "Identifier"
      ; "schema", `Assoc [ "type", `String "integer" ]
      ]
  in
  let query = set parameter "in" (`String "query") in
  let header = set parameter "in" (`String "header") in
  let operation parameters =
    `Assoc
      [ "parameters", `List parameters
      ; "responses", `Assoc [ "200", `Assoc [ "description", `String "OK" ] ]
      ]
  in
  let doc operations = `Assoc [ "paths", `Assoc [ "/items/{id}", `Assoc operations ] ] in
  let path doc = doc |> member "paths" |> member "/items/{id}" in
  let base =
    doc
      [ "get", operation [ parameter; query; header ]
      ; "delete", operation [ parameter; query; header ]
      ]
  in
  let normalized = Openapi_normalize.document base in
  assert (equal (path normalized |> member "parameters") (`List [ parameter ]));
  assert (
    equal
      (path normalized |> member "get" |> member "parameters")
      (`List [ query; header ]));
  assert (
    equal
      (Check.operation_exn base ~path:"/items/{id}" ~meth:"get")
      (Check.operation_exn normalized ~path:"/items/{id}" ~meth:"get"));
  assert (equal normalized (Openapi_normalize.document normalized));
  let differs =
    [ set parameter "description" (`String "Different")
    ; set parameter "required" (`Bool false)
    ; set parameter "schema" (`Assoc [ "type", `String "integer"; "minimum", `Int 1 ])
    ; set parameter "style" (`String "simple")
    ]
  in
  List.iter differs ~f:(fun different ->
    let original =
      doc [ "get", operation [ parameter ]; "delete", operation [ different ] ]
    in
    let after = Openapi_normalize.document original in
    assert (equal (path after |> member "parameters") `Null);
    assert (equal (projection original) (projection after)));
  List.iter
    [ doc [ "get", operation [ parameter ] ]
    ; doc [ "get", operation [ parameter ]; "delete", operation [] ]
    ; doc [ "get", operation [ query; header ]; "delete", operation [ query; header ] ]
    ]
    ~f:(fun original ->
      let after = Openapi_normalize.document original in
      assert (equal (path after |> member "parameters") `Null);
      assert (equal (projection original) (projection after)));
  (* Existing Path Item definitions are inherited; operation definitions override
     them by identity, and cannot be discarded by lifting another definition. *)
  let inherited = set parameter "description" (`String "Inherited") in
  let original =
    doc
      [ "parameters", `List [ inherited ]
      ; "summary", `String "Items"
      ; "get", operation [ parameter ]
      ; "delete", operation [ parameter ]
      ]
  in
  let after = Openapi_normalize.document original in
  assert (equal (path after |> member "parameters") (`List [ inherited ]));
  assert (equal (projection original) (projection after));
  let effective =
    Check.operation_exn after ~path:"/items/{id}" ~meth:"get" |> member "parameters"
  in
  assert (equal effective (`List [ parameter ]));
  let inherited_only = doc [ "parameters", `List [ inherited ]; "get", operation [] ] in
  assert (
    equal
      (Check.operation_exn inherited_only ~path:"/items/{id}" ~meth:"get"
       |> member "parameters")
      (`List [ inherited ]));
  let descriptions =
    [ ( "same"
      , set (set (operation []) "summary" (`String "Same")) "description" (`String "Same")
      )
    ; "empty", set (operation []) "description" (`String "")
    ; ( "different"
      , set
          (set (operation []) "summary" (`String "Summary"))
          "description"
          (`String "Details") )
    ; ( "whitespace"
      , set
          (set (operation []) "summary" (`String "Same"))
          "description"
          (`String "Same ") )
    ]
  in
  List.iter descriptions ~f:(fun (name, operation) ->
    let original = doc [ "get", operation ] in
    let after = Openapi_normalize.document original in
    let description = path after |> member "get" |> member "description" in
    if List.mem [ "same"; "empty" ] name ~equal:String.equal then
      assert (equal description `Null)
    else
      assert (equal description (member "description" operation));
    assert (equal (projection original) (projection after)))
;;

let () = QCheck_base_runner.run_tests_main [ normalization ]
