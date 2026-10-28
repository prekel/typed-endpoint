open! Base
module G = Typed_endpoint_openapi

let json = Yojson.Safe.from_string

let config raw =
  match G.Config.of_yojson (json raw) with
  | Ok x -> x
  | Error es ->
    Stdlib.failwith (String.concat ~sep:"; " (List.map es ~f:G.Diagnostic.to_string))
;;

let document schema =
  `Assoc
    [ "openapi", `String "3.0.3"
    ; "info", `Assoc [ "title", `String "Test"; "version", `String "1" ]
    ; ( "paths"
      , `Assoc
          [ ( "/pets"
            , `Assoc
                [ ( "get"
                  , `Assoc
                      [ ( "responses"
                        , `Assoc
                            [ ( "200"
                              , `Assoc
                                  [ "description", `String "OK"
                                  ; ( "content"
                                    , `Assoc
                                        [ "application/json", `Assoc [ "schema", schema ]
                                        ] )
                                  ] )
                            ] )
                      ] )
                ] )
          ] )
    ]
;;

let generate ?config schema = G.generate ?config (document schema)

let output files path =
  (List.find_exn files ~f:(fun (f : G.Generated_file.t) -> String.equal f.path path))
    .contents
;;

let require = function
  | Ok x -> x
  | Error es ->
    Stdlib.failwith (String.concat ~sep:"; " (List.map es ~f:G.Diagnostic.to_string))
;;

let print_error = function
  | Ok _ -> Stdlib.print_endline "unexpected success"
  | Error es -> List.iter es ~f:(fun e -> Stdlib.print_endline (G.Diagnostic.to_string e))
;;

let%expect_test "declarative names and identities use arbitrary fields" =
  let c =
    config
      {|{"naming":{"type_name":{"select":"/origin/0","transform":"json_pointer_last_segment"},"schema_identity":{"select":"/origin/0"}}}|}
  in
  let result =
    generate ~config:c (json {|{"origin":["#/models/Pet"],"type":"string"}|}) |> require
  in
  let dto = output result "dto.mli" in
  assert (String.is_substring dto ~substring:"module Pet : sig");
  Stdlib.print_endline "Pet";
  [%expect {| Pet |}];
  let c = config {|{"naming":{"type_name":{"select":"/title"}}}|} in
  let dto =
    generate ~config:c (json {|{"title":"Named","type":"string"}|}) |> require
    |> fun fs -> output fs "dto.ml"
  in
  assert (String.is_substring dto ~substring:"Named");
  assert (String.is_substring dto ~substring:"module Named = struct");
  Stdlib.print_endline "Named";
  [%expect {| Named |}]
;;

let%expect_test "missing metadata falls back to operation location" =
  let c = config {|{"naming":{"type_name":{"select":"/absent"}}}|} in
  let dto =
    generate ~config:c (json {|{"type":"string"}|}) |> require |> fun fs ->
    output fs "dto.mli"
  in
  assert (String.is_substring dto ~substring:"module Get_pets_response_200 : sig");
  Stdlib.print_endline "Get_pets_response_200";
  [%expect {| Get_pets_response_200 |}]
;;

let%expect_test "selected malformed metadata is diagnosed" =
  let c = config {|{"naming":{"type_name":{"select":"/title"}}}|} in
  print_error (generate ~config:c (json {|{"title":3,"type":"string"}|}));
  [%expect
    {| #/paths/~1pets/get/responses/200/content/application~1json/schema [type]: expected string |}];
  (match
     G.Config.of_yojson (json {|{"naming":{"type_name":{"select":"/bad~2escape"}}}|})
   with
   | Ok _ -> assert false
   | Error es ->
     List.iter es ~f:(fun e -> Stdlib.print_endline (G.Diagnostic.to_string e)));
  [%expect {| #/config/naming [selector]: invalid JSON Pointer escape |}]
;;

let%expect_test "remaining references and unsafe compositions fail" =
  print_error (generate (json {|{"$ref":"#/components/schemas/Pet"}|}));
  [%expect
    {| #/paths/~1pets/get/responses/200/content/application~1json/schema/$ref [schema]: unsupported schema keyword $ref |}];
  print_error
    (generate
       (json
          {|{"allOf":[{"type":"object","properties":{"a":{"type":"string"}},"additionalProperties":false},{"type":"object","properties":{"b":{"type":"string"}}}]}|}));
  [%expect
    {| #/paths/~1pets/get/responses/200/content/application~1json/schema [allOf]: closed branches forbid properties from other branches |}]
;;

let%expect_test "names, collisions and output are independent of object order" =
  let c =
    config
      {|{"naming":{"type_name":{"select":"/x-name"},"schema_identity":{"select":"/x-id"}}}|}
  in
  let schema =
    json
      {|{"type":"object","properties":{"a":{"type":"string","x-name":"Value","x-id":"A"},"b":{"type":"integer","x-name":"Value","x-id":"B"}},"additionalProperties":false}|}
  in
  let rec reverse = function
    | `Assoc xs -> `Assoc (List.rev_map xs ~f:(fun (k, v) -> k, reverse v))
    | `List xs -> `List (List.map xs ~f:reverse)
    | x -> x
  in
  let a = generate ~config:c schema |> require
  and b = generate ~config:c (reverse schema) |> require in
  assert (
    List.equal
      (fun (a : G.Generated_file.t) b ->
         String.equal a.path b.path && String.equal a.contents b.contents)
      a
      b);
  let dto = output a "dto.mli" in
  assert (String.is_substring dto ~substring:"Value__7fc56270");
  assert (String.is_substring dto ~substring:"Value__9d5ed678");
  Stdlib.print_endline "stable";
  [%expect {| stable |}]
;;

let%expect_test "one identity cannot hide incompatible wire types" =
  let c = config {|{"naming":{"schema_identity":{"select":"/x-id"}}}|} in
  print_error
    (generate
       ~config:c
       (json
          {|{"type":"object","properties":{"a":{"type":"string","x-id":"same"},"b":{"type":"integer","x-id":"same"}}}|}));
  [%expect
    {| #/paths/~1pets/get/responses/200/content/application~1json/schema/properties/b [identity]: incompatible definitions for same |}]
;;

let%expect_test "security is never silently removed" =
  let root = document (json {|{"type":"string"}|}) in
  let protected =
    match root with
    | `Assoc fields -> `Assoc (("security", json {|[{"bearer":[]}]|}) :: fields)
    | _ -> assert false
  in
  print_error (G.generate protected);
  [%expect {| #/paths/~1pets/get [security]: authorization generation is deferred |}];
  let malformed =
    match root with
    | `Assoc fields -> `Assoc (("security", `Null) :: fields)
    | _ -> assert false
  in
  print_error (G.generate malformed);
  [%expect {| #/paths/~1pets/get/security [security]: expected security array |}];
  let operation =
    Yojson.Safe.Util.(
      protected |> member "paths" |> member "/pets" |> member "get" |> to_assoc)
  in
  let paths =
    `Assoc [ "/pets", `Assoc [ "get", `Assoc (("security", `List []) :: operation) ] ]
  in
  let public =
    match protected with
    | `Assoc fs ->
      `Assoc
        (("paths", paths)
         :: List.filter fs ~f:(fun (k, _) -> not (String.equal k "paths")))
    | _ -> assert false
  in
  ignore (require (G.generate public) : G.Generated_file.t list);
  Stdlib.print_endline "explicit public operation";
  [%expect {| explicit public operation |}]
;;

let replace json key value =
  `Assoc
    ((key, value)
     :: List.filter (Yojson.Safe.Util.to_assoc json) ~f:(fun (k, _) ->
       not (String.equal k key)))
;;

let modern schema = replace (document schema) "openapi" (`String "3.2.1")
let source ?group name document : G.Source.t = { name; group; document }

let%expect_test "multiple sources share explicit identities independent of input order" =
  let c =
    config
      {|{"naming":{"type_name":{"select":"/x-name"},"schema_identity":{"select":"/x-id"}}}|}
  in
  let shared = json {|{"type":"string","x-name":"Shared","x-id":"urn:shared"}|} in
  let a = source ~group:"Catalog" "catalog" (document shared) in
  let b =
    source
      ~group:"Admin"
      "admin"
      (replace
         (modern shared)
         "paths"
         (json
            {|{"/admin":{"get":{"responses":{"200":{"description":"OK","content":{"application/json":{"schema":{"type":"string","x-name":"Shared","x-id":"urn:shared"}}}}}}}}|}))
  in
  let files = G.generate_sources ~config:c [ a; b ] |> require in
  let reversed = G.generate_sources ~config:c [ b; a ] |> require in
  assert (
    List.equal
      (fun (a : G.Generated_file.t) b -> String.equal a.contents b.contents)
      files
      reversed);
  assert (
    String.is_substring (output files "server.mli") ~substring:"module Catalog : sig");
  assert (String.is_substring (output files "server.mli") ~substring:"module Admin : sig");
  assert (
    List.length
      (String.substr_index_all
         ~may_overlap:false
         (output files "dto.mli")
         ~pattern:"module Shared : sig")
    = 1);
  Stdlib.print_endline "one shared DTO, two groups, stable output";
  [%expect {| one shared DTO, two groups, stable output |}]
;;

let%expect_test "source-local fallback IDs cannot accidentally share incompatible schemas"
  =
  let a = source "a" (document (json {|{"type":"string"}|})) in
  let b = source "b" (document (json {|{"type":"integer"}|})) in
  print_error (G.generate_sources [ a; b ]);
  [%expect {| #/sources/a/paths/~1pets/get [route]: duplicate route GET /pets |}];
  let b =
    { b with
      document =
        replace
          b.document
          "paths"
          (json
             {|{"/pets":{"post":{"responses":{"200":{"description":"OK","content":{"application/json":{"schema":{"type":"integer"}}}}}}}}|})
    }
  in
  let files = G.generate_sources [ a; b ] |> require in
  assert (String.is_substring (output files "dto.mli") ~substring:"type t = string");
  assert (String.is_substring (output files "dto.mli") ~substring:"type t = int64");
  Stdlib.print_endline "local schemas remain distinct";
  [%expect {| local schemas remain distinct |}]
;;

let%expect_test "shared schema conflicts include the source name" =
  let c = config {|{"naming":{"schema_identity":{"select":"/x-id"}}}|} in
  print_error
    (G.generate_sources
       ~config:c
       [ source "a" (document (json {|{"type":"string","x-id":"shared"}|}))
       ; source "b" (modern (json {|{"type":"integer","x-id":"shared"}|}))
       ]);
  [%expect
    {| #/sources/b/paths/~1pets/get/responses/200/content/application~1json/schema [identity]: incompatible definitions for shared |}]
;;

let%expect_test "3.2.1 nullable type unions, string const and numeric exclusive bounds" =
  let schema =
    json
      {|{"type":"object","properties":{"note":{"type":["string","null"]},"kind":{"const":"ok"},"score":{"type":"number","exclusiveMinimum":1},"nothing":{"type":"null"},"anything":true},"additionalProperties":false}|}
  in
  let files = G.generate (modern schema) |> require in
  let dto = output files "dto.mli" in
  assert (String.is_substring dto ~substring:"Support.presence");
  assert (String.is_substring dto ~substring:"| Ok");
  assert (String.is_substring dto ~substring:"type t = unit");
  Stdlib.print_endline "generated";
  [%expect {| generated |}];
  print_error (G.generate (modern (json {|{"type":["string","integer"]}|})));
  [%expect
    {| #/paths/~1pets/get/responses/200/content/application~1json/schema/type [type]: multiple non-null types are not supported |}];
  print_error (G.generate (modern (json {|{"type":"string","nullable":true}|})));
  [%expect
    {| #/paths/~1pets/get/responses/200/content/application~1json/schema/nullable [schema]: use a null type union in OpenAPI 3.2.1 |}];
  print_error (G.generate (modern (json {|{"type":"number","exclusiveMinimum":true}|})));
  [%expect
    {| #/paths/~1pets/get/responses/200/content/application~1json/schema/exclusiveMinimum [schema]: expected numeric exclusive bound |}];
  print_error
    (G.generate
       (replace (modern (`Assoc [])) "jsonSchemaDialect" (`String "urn:unknown")));
  [%expect {| #/jsonSchemaDialect [dialect]: unsupported JSON Schema dialect |}]
;;

let%expect_test "3.2.1 string const selects discriminated object branches" =
  let schema =
    json
      {|{"oneOf":[{"type":"object","properties":{"kind":{"const":"cat"}},"required":["kind"]},{"type":"object","properties":{"kind":{"const":"dog"}},"required":["kind"]}],"discriminator":{"propertyName":"kind"}}|}
  in
  let files = G.generate (modern schema) |> require in
  assert (String.is_substring (output files "dto.mli") ~substring:"| Cat of");
  Stdlib.print_endline "discriminated union";
  [%expect {| discriminated union |}]
;;

let%expect_test "3.2.1 naming selectors preserve standard constraints" =
  let c = config {|{"naming":{"type_name":{"select":"/const"}}}|} in
  let files = G.generate ~config:c (modern (json {|{"const":"ok"}|})) |> require in
  assert (String.is_substring (output files "dto.mli") ~substring:"module Ok : sig");
  assert (String.is_substring (output files "dto.ml") ~substring:{|\"const\":\"ok\"|});
  Stdlib.print_endline "const retained";
  [%expect {| const retained |}];
  print_error (G.generate (modern (json {|{"const":"ok","type":"integer"}|})));
  [%expect
    {| #/paths/~1pets/get/responses/200/content/application~1json/schema [const]: const conflicts with type |}];
  print_error (G.generate (modern (json {|{"const":null,"type":"string"}|})));
  [%expect
    {| #/paths/~1pets/get/responses/200/content/application~1json/schema [const]: const conflicts with type |}]
;;

let%expect_test "unsupported 3.2.1 HTTP semantics are rejected" =
  let root = modern (json {|{"type":"string"}|}) in
  let paths value = G.generate (replace root "paths" (json value)) in
  print_error
    (paths
       {|{"/pets":{"get":{"parameters":[{"name":"q","in":"querystring","schema":{"type":"string"}}],"responses":{"200":{"description":"OK"}}}}}|});
  [%expect
    {| #/paths/~1pets/get/parameters/0 [parameter]: unsupported parameter location |}];
  print_error
    (paths
       {|{"/pets":{"additionalOperations":{"COPY":{"responses":{"200":{"description":"OK"}}}}}}|});
  [%expect {| #/paths/~1pets/additionalOperations [method]: unsupported HTTP method |}];
  print_error
    (paths
       {|{"/pets":{"get":{"responses":{"200":{"description":"OK","content":{"application/json":{"itemSchema":{"type":"string"}}}}}}}}|});
  [%expect
    {| #/paths/~1pets/get/responses/200 [content]: streaming itemSchema is not supported |}];
  print_error (G.generate (replace root "webhooks" (json {|{"event":{}}|})));
  [%expect {| #/webhooks [unsupported]: webhook generation is not supported |}]
;;

let%expect_test "source names are required to distinguish documents" =
  print_error (G.generate_sources []);
  [%expect {| #/sources [source]: at least one source is required |}];
  let root = document (json {|{"type":"string"}|}) in
  print_error (G.generate_sources [ source "same" root; source "same" root ]);
  [%expect {| #/sources [source]: source names must be unique |}]
;;
