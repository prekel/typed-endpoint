open! Base
open Typed_endpoint
module S = Json_schema

let print schema = S.to_yojson schema |> Yojson.Safe.to_string |> Stdlib.print_endline
let print_json value = Yojson.Safe.to_string value |> Stdlib.print_endline
let member = Yojson.Safe.Util.member

let print_error f =
  match f () with
  | _ -> Stdlib.failwith "expected a schema error"
  | exception Json_schema.Invalid_schema error -> Stdlib.print_endline error
;;

let%expect_test "schema errors use the registered public exception printer" =
  let error =
    match S.string ~min_length:(-1) () with
    | _ -> Stdlib.failwith "expected an invalid declaration"
    | exception (S.Invalid_schema _ as error) -> error
  in
  Stdlib.Printexc.to_string error |> Stdlib.print_endline;
  [%expect
    {| Typed_endpoint.Json_schema.Invalid_schema: minLength must be greater than or equal to zero |}]
;;

let%expect_test "Base exception printing retains the schema diagnostic" =
  Exn.to_string (S.Invalid_schema "enum must not be empty") |> Stdlib.print_endline;
  [%expect {| ("Typed_endpoint.Json_schema.Invalid_schema: enum must not be empty") |}]
;;

exception Encoder_error of string

let%test_unit "the schema printer declines unrelated exceptions" =
  let error = Encoder_error "external" in
  assert (Option.is_none (Stdlib.Printexc.use_printers error));
  assert (String.is_substring (Stdlib.Printexc.to_string error) ~substring:"Encoder_error")
;;

let%test_unit "user encoder exceptions propagate unchanged" =
  let error = Encoder_error "encoding failed" in
  let encode _ = raise error in
  List.iter
    [ (fun () -> S.with_const ~encode `Null S.any)
    ; (fun () -> S.with_enum ~encode [ `Null ] S.any)
    ; (fun () -> S.with_examples ~encode [ `Null ] S.any)
    ]
    ~f:(fun construct ->
      match construct () with
      | _ -> Stdlib.failwith "expected an encoder error"
      | exception caught -> assert (phys_equal caught error))
;;

let validator schema =
  let json = Yojson.Safe.to_basic (S.to_yojson schema) in
  (match Jsonschema.validate Jsonschema.draft2020_12_validator json with
   | Ok () -> ()
   | Error error -> Stdlib.failwith (Jsonschema.Validation_error.to_string error));
  match Jsonschema.create_validator_from_json ~schema:json () with
  | Ok validator -> validator
  | Error error ->
    Stdlib.failwith (Stdlib.Format.asprintf "%a" Jsonschema.pp_compile_error error)
;;

let check schema ~accept ~reject =
  let validator = validator schema in
  List.iter accept ~f:(fun value ->
    match Jsonschema.validate validator value with
    | Ok () -> ()
    | Error error -> Stdlib.failwith (Jsonschema.Validation_error.to_string error));
  List.iter reject ~f:(fun value ->
    assert (Result.is_error (Jsonschema.validate validator value)))
;;

let%expect_test "string patterns and content encoding are literal annotations" =
  let schema = S.string ~pattern:"^[a-z]+$" ~content_encoding:"base64" () in
  print schema;
  [%expect {| {"type":"string","pattern":"^[a-z]+$","contentEncoding":"base64"} |}];
  check schema ~accept:[ `String "abc" ] ~reject:[ `String "a1"; `String "ABC" ];
  check
    (S.string ~pattern:"cat" ())
    ~accept:[ `String "a cat!" ]
    ~reject:[ `String "dog" ];
  print (S.string ~pattern:"" ());
  [%expect {| {"type":"string","pattern":""} |}];
  print_error (fun () -> S.string ~content_encoding:" " ());
  [%expect {| contentEncoding must not be empty |}]
;;

let%expect_test "strict numeric bounds and divisibility" =
  let schema =
    S.integer ~minimum:0 ~exclusive_minimum:1 ~exclusive_maximum:8 ~multiple_of:2 ()
  in
  print schema;
  [%expect
    {| {"type":"integer","minimum":0,"exclusiveMinimum":1,"exclusiveMaximum":8,"multipleOf":2} |}];
  check schema ~accept:[ `Int 2; `Int 6 ] ~reject:[ `Int 0; `Int 1; `Int 3; `Int 8 ];
  let schema = S.number ~exclusive_minimum:0. ~maximum:1. ~multiple_of:0.25 () in
  print schema;
  [%expect {| {"type":"number","maximum":1.0,"exclusiveMinimum":0.0,"multipleOf":0.25} |}];
  check schema ~accept:[ `Float 0.25; `Float 1. ] ~reject:[ `Float 0.; `Float 0.3 ];
  print_error (fun () -> S.integer ~minimum:4 ~exclusive_maximum:4 ());
  [%expect {| numeric bounds must describe a non-empty range |}];
  print_error (fun () -> S.integer ~exclusive_minimum:4 ~default:4 ());
  [%expect {| default must be within the declared bounds |}];
  print_error (fun () -> S.integer ~multiple_of:0 ());
  [%expect {| multipleOf must be greater than zero |}];
  print_error (fun () -> S.number ~exclusive_minimum:Float.infinity ());
  [%expect {| exclusiveMinimum must be finite |}];
  print_error (fun () -> S.number ~multiple_of:Float.nan ());
  [%expect {| multipleOf must be finite |}]
;;

let%expect_test "int64 bounds retain all decimal digits" =
  print
    (S.int64
       ~exclusive_minimum:9007199254740993L
       ~exclusive_maximum:9223372036854775807L
       ~multiple_of:3L
       ());
  [%expect
    {| {"type":"integer","exclusiveMinimum":9007199254740993,"exclusiveMaximum":9223372036854775807,"multipleOf":3} |}];
  print_error (fun () -> S.int64 ~multiple_of:(-1L) ());
  [%expect {| multipleOf must be greater than zero |}]
;;

let%expect_test "prefix items and tail share one array schema" =
  let schema =
    S.list
      ~prefix_items:[ S.as_json (S.string ()); S.as_json (S.integer ()) ]
      ~items:(S.as_json (S.boolean ()))
      ()
  in
  print schema;
  [%expect
    {| {"type":"array","items":{"type":"boolean"},"prefixItems":[{"type":"string"},{"type":"integer"}]} |}];
  check
    schema
    ~accept:[ `List []; `List [ `String "x" ]; `List [ `String "x"; `Int 1; `Bool true ] ]
    ~reject:[ `List [ `Int 1 ]; `List [ `String "x"; `Int 1; `String "tail" ] ];
  let closed = S.array ~prefix_items:[ S.as_json (S.string ()) ] ~items:S.never () in
  print closed;
  [%expect {| {"type":"array","items":false,"prefixItems":[{"type":"string"}]} |}];
  check
    closed
    ~accept:[ `List []; `List [ `String "x" ] ]
    ~reject:[ `List [ `String "x"; `String "y" ] ];
  print_error (fun () -> S.array ~prefix_items:[] ~items:S.any ());
  [%expect {| prefixItems must not be empty |}]
;;

let%expect_test "contains occurrence bounds and unique items" =
  let schema =
    S.array
      ~items:(S.integer ())
      ~unique_items:true
      ~contains:(S.integer ~minimum:10 ())
      ~min_contains:0
      ~max_contains:1
      ()
  in
  print schema;
  [%expect
    {| {"type":"array","items":{"type":"integer"},"uniqueItems":true,"contains":{"type":"integer","minimum":10},"minContains":0,"maxContains":1} |}];
  check
    schema
    ~accept:[ `List []; `List [ `Int 1; `Int 10 ] ]
    ~reject:[ `List [ `Int 10; `Int 11 ]; `List [ `Int 1; `Int 1 ] ];
  check
    (S.list ~items:(S.integer ()) ~contains:(S.integer ~minimum:10 ()) ())
    ~accept:[ `List [ `Int 10 ] ]
    ~reject:[ `List []; `List [ `Int 1 ] ];
  print_error (fun () -> S.list ~items:S.any ~max_contains:1 ());
  [%expect {| minContains and maxContains require contains |}];
  print_error (fun () -> S.list ~items:S.any ~contains:S.any ~max_contains:0 ());
  [%expect {| minContains must be less than or equal to maxContains |}];
  print_error (fun () -> S.list ~items:S.any ~contains:S.any ~min_contains:(-1) ());
  [%expect {| minContains must be greater than or equal to zero |}]
;;

let%expect_test "enum and const constrain entire collections" =
  let encode values = `List (List.map values ~f:(fun value -> `Int value)) in
  let base = S.list ~items:(S.integer ~minimum:0 ()) () in
  let schema = S.with_enum ~encode [ [ 1; 2 ]; [] ] base in
  print schema;
  [%expect
    {| {"allOf":[{"type":"array","items":{"type":"integer","minimum":0}},{"enum":[[1,2],[]]}]} |}];
  check
    schema
    ~accept:[ `List [ `Int 1; `Int 2 ]; `List [] ]
    ~reject:[ `List [ `Int 1 ]; `List [ `Int 2; `Int 1 ] ];
  let schema = S.with_const ~encode [ -1 ] base in
  print schema;
  [%expect
    {| {"allOf":[{"type":"array","items":{"type":"integer","minimum":0}},{"const":[-1]}]} |}];
  check schema ~accept:[] ~reject:[ `List [ `Int (-1) ]; `List [] ];
  let encode value = `Intlit (Int64.to_string value) in
  let schema =
    S.with_enum ~encode [ 9007199254740992L; 9007199254740993L ] (S.int64 ())
  in
  S.to_yojson schema
  |> member "allOf"
  |> Yojson.Safe.Util.to_list
  |> List.last_exn
  |> print_json;
  [%expect {| {"enum":[9007199254740992,9007199254740993]} |}]
;;

let%expect_test "literal checks reject invalid JSON and semantic duplicates" =
  print_error (fun () -> S.with_enum ~encode:Fn.id [] S.any);
  [%expect {| enum must not be empty |}];
  print_error (fun () -> S.with_enum ~encode:Fn.id [ `Int 1; `Float 1. ] S.any);
  [%expect {| enum contains duplicate JSON value |}];
  print_error (fun () ->
    S.with_enum
      ~encode:Fn.id
      [ `Assoc [ "a", `Int 1; "b", `Null ]; `Assoc [ "b", `Null; "a", `Intlit "1" ] ]
      S.any);
  [%expect {| enum contains duplicate JSON value |}];
  print_error (fun () -> S.with_const ~encode:Fn.id (`Float Float.infinity) S.any);
  [%expect {| JSON value must contain only finite floats |}];
  print_error (fun () -> S.with_const ~encode:Fn.id (`Intlit "01") S.any);
  [%expect {| JSON value must contain only valid JSON integer literals |}];
  print_error (fun () ->
    S.with_const ~encode:Fn.id (`Assoc [ "a", `Null; "a", `Null ]) S.any);
  [%expect {| JSON object contains duplicate name a |}]
;;

let%expect_test "dictionary patterns preserve the base value schema" =
  let schema =
    S.dictionary ~values:(S.integer ~minimum:0 ())
    |> S.with_dictionary_constraints
         ~property_names:(S.string ~pattern:"^[a-z]+$" ())
         ~pattern_properties:
           [ "^a", S.integer ~maximum:10 (); "z$", S.integer ~minimum:5 () ]
         ~min_properties:1
         ~max_properties:2
  in
  print schema;
  [%expect
    {| {"allOf":[{"type":"object","additionalProperties":{"type":"integer","minimum":0}},{"propertyNames":{"type":"string","pattern":"^[a-z]+$"},"patternProperties":{"^a":{"type":"integer","maximum":10},"z$":{"type":"integer","minimum":5}},"minProperties":1,"maxProperties":2}]} |}];
  check
    schema
    ~accept:[ `Assoc [ "az", `Int 7 ]; `Assoc [ "other", `Int 20 ] ]
    ~reject:
      [ `Assoc []
      ; `Assoc [ "a", `Int (-1) ]
      ; `Assoc [ "az", `Int 3 ]
      ; `Assoc [ "az", `Int 12 ]
      ; `Assoc [ "A", `Int 1 ]
      ; `Assoc [ "a", `Int 1; "b", `Int 2; "c", `Int 3 ]
      ];
  print_error (fun () ->
    S.object_ ~pattern_properties:[ "a", S.pack S.any; "a", S.pack S.any ] ());
  [%expect {| patternProperties contains duplicate name a |}];
  print_error (fun () -> S.object_ ~min_properties:2 ~max_properties:1 ());
  [%expect {| minProperties must be less than or equal to maxProperties |}]
;;

let%expect_test "object dependencies validate the whole object" =
  let dependency = S.object_ ~properties:[ "b", S.pack (S.integer ~minimum:5 ()) ] () in
  let schema =
    S.object_
      ~properties:[ "a", S.pack (S.integer ()); "b", S.pack (S.integer ()) ]
      ~additional_properties:S.Deny
      ~dependent_required:[ "a", [ "b" ] ]
      ~dependent_schemas:[ "a", S.pack dependency ]
      ()
  in
  S.to_yojson schema |> member "dependentRequired" |> print_json;
  [%expect {| {"a":["b"]} |}];
  S.to_yojson schema |> member "dependentSchemas" |> print_json;
  [%expect
    {| {"a":{"type":"object","properties":{"b":{"type":"integer","minimum":5}},"required":[],"additionalProperties":true}} |}];
  check
    schema
    ~accept:[ `Assoc []; `Assoc [ "b", `Int 1 ]; `Assoc [ "a", `Int 0; "b", `Int 5 ] ]
    ~reject:
      [ `Assoc [ "a", `Int 0 ]
      ; `Assoc [ "a", `Int 0; "b", `Int 4 ]
      ; `Assoc [ "extra", `Null ]
      ];
  print_error (fun () -> S.object_ ~dependent_required:[ "a", [ "b"; "b" ] ] ());
  [%expect {| dependentRequired contains duplicate name b |}];
  print_error (fun () ->
    S.object_ ~properties:[ "a", S.pack S.any; "a", S.pack S.any ] ());
  [%expect {| properties contains duplicate name a |}]
;;

let%test_unit "additional properties apply only to unmatched object keys" =
  let schema =
    S.object_
      ~properties:[ "name", S.pack (S.string ()) ]
      ~required:[ "name" ]
      ~pattern_properties:[ "^flag", S.pack (S.boolean ()) ]
      ~additional_properties:(S.Schema (S.pack (S.integer ())))
      ()
  in
  check
    schema
    ~accept:[ `Assoc [ "name", `String "x"; "flagA", `Bool true; "count", `Int 1 ] ]
    ~reject:[ `Assoc []; `Assoc [ "name", `String "x"; "count", `String "bad" ] ];
  let schema =
    S.dictionary ~values:(S.integer ())
    |> S.with_dictionary_constraints
         ~dependent_required:[ "a", [ "b" ] ]
         ~dependent_schemas:[ "a", S.pack (S.object_ ~required:[ "c" ] ()) ]
  in
  check
    schema
    ~accept:[ `Assoc []; `Assoc [ "a", `Int 1; "b", `Int 2; "c", `Int 3 ] ]
    ~reject:[ `Assoc [ "a", `Int 1; "b", `Int 2 ] ]
;;

let%expect_test "composition, complement and conditionals" =
  let bounded = S.all_of [ S.integer ~minimum:0 (); S.integer ~maximum:10 () ] in
  print bounded;
  [%expect
    {| {"allOf":[{"type":"integer","minimum":0},{"type":"integer","maximum":10}]} |}];
  check bounded ~accept:[ `Int 0; `Int 10 ] ~reject:[ `Int (-1); `Int 11 ];
  let excluded = S.with_not ~schema:(S.integer ~minimum:5 ()) bounded in
  check excluded ~accept:[ `Int 0; `Int 4 ] ~reject:[ `Int 5; `String "x" ];
  check (S.not_ (S.integer ())) ~accept:[ `String "x"; `Null ] ~reject:[ `Int 1 ];
  let mixed = S.any_of [ S.as_json (S.string ()); S.as_json (S.integer ()) ] in
  check mixed ~accept:[ `String "x"; `Int 1 ] ~reject:[ `Bool true ];
  let overlap = S.one_of [ S.integer ~minimum:0 (); S.integer ~maximum:10 () ] in
  check overlap ~accept:[ `Int (-1); `Int 11 ] ~reject:[ `Int 5 ];
  let conditional =
    S.if_then_else
      ~if_:(S.integer ~minimum:0 ())
      ~then_:(S.integer ~multiple_of:2 ())
      ~else_:(S.integer ~maximum:(-10) ())
  in
  print conditional;
  [%expect
    {| {"if":{"type":"integer","minimum":0},"then":{"type":"integer","multipleOf":2},"else":{"type":"integer","maximum":-10}} |}];
  check conditional ~accept:[ `Int 2; `Int (-10) ] ~reject:[ `Int 1; `Int (-1) ];
  print_error (fun () -> S.all_of []);
  [%expect {| allOf must not be empty |}];
  print_error (fun () -> S.any_of []);
  [%expect {| anyOf must not be empty |}];
  print_error (fun () -> S.one_of []);
  [%expect {| oneOf must not be empty |}]
;;

let local name (schema : 'a S.t) : 'a S.t =
  S.Deriver.root_ref ~root:name ~definitions:[ name, S.pack schema ]
;;

let%expect_test "composition lifts unscoped definitions and rejects conflicts" =
  let left : string S.t = local "left" (S.string ~min_length:1 ()) in
  let right : string S.t = local "right" (S.string ~max_length:3 ()) in
  let schema = S.all_of [ left; right ] in
  print schema;
  [%expect
    {| {"$defs":{"left":{"type":"string","minLength":1},"right":{"type":"string","maxLength":3}},"allOf":[{"$ref":"#/$defs/left"},{"$ref":"#/$defs/right"}]} |}];
  check schema ~accept:[ `String "abc" ] ~reject:[ `String ""; `String "abcd" ];
  let repeated = S.all_of [ left; left ] in
  check repeated ~accept:[ `String "a" ] ~reject:[ `String "" ];
  let conflict : string S.t = local "left" (S.string ~min_length:2 ()) in
  print_error (fun () -> S.all_of [ left; conflict ]);
  [%expect {| conflicting local definition left |}];
  let objects =
    S.object_
      ~properties:[ "left", S.pack left; "right", S.pack right ]
      ~required:[ "left"; "right" ]
      ()
  in
  check
    objects
    ~accept:[ `Assoc [ "left", `String "a"; "right", `String "abc" ] ]
    ~reject:[ `Assoc [ "left", `String ""; "right", `String "abc" ] ];
  check
    (S.list ~items:left ())
    ~accept:[ `List [ `String "a" ] ]
    ~reject:[ `List [ `String "" ] ]
;;

let%test_unit "embedded resources and opaque literals retain their scopes" =
  let first : string S.t =
    local "value" (S.string ()) |> S.Deriver.with_id "urn:typed-endpoint:test:first"
  in
  let second : int S.t =
    local "value" (S.integer ()) |> S.Deriver.with_id "urn:typed-endpoint:test:second"
  in
  let schema = S.all_of [ S.as_json first; S.as_json second ] |> S.to_yojson in
  assert (Poly.equal (member "$defs" schema) `Null);
  assert (
    List.equal
      Yojson.Safe.equal
      (member "allOf" schema |> Yojson.Safe.Util.to_list)
      [ S.to_yojson first; S.to_yojson second ]);
  let data = `Assoc [ "$defs", `Assoc [ "value", `Int 1 ]; "$ref", `String "literal" ] in
  let literal = S.with_const ~encode:Fn.id data S.any in
  let composed = S.all_of [ literal; S.any ] |> S.to_yojson in
  assert (Poly.equal (member "$defs" composed) `Null);
  assert (
    Yojson.Safe.equal
      (member "allOf" composed |> Yojson.Safe.Util.to_list |> List.hd_exn)
      (S.to_yojson literal))
;;

let%test_unit "nullable accepts null for every new applicator" =
  let schemas =
    [ S.all_of [ S.as_json (S.string ()) ]
    ; S.one_of [ S.as_json (S.string ()); S.as_json (S.integer ()) ]
    ; S.with_not ~schema:S.null S.any
    ; S.with_const ~encode:Fn.id (`Int 1) S.any
    ; S.with_enum ~encode:Fn.id [ `Int 1 ] S.any
    ; S.if_then_else ~if_:S.any ~then_:(S.as_json (S.string ())) ~else_:S.never
    ; S.never
    ]
  in
  List.iter schemas ~f:(fun schema ->
    let nullable = S.nullable schema in
    check nullable ~accept:[ `Null ] ~reject:[];
    assert (S.equal nullable (S.nullable nullable)))
;;

let%test_unit "nullable preserves applicators adjacent to a primitive type" =
  List.iter
    [ S.Unsafe.of_yojson
        (`Assoc
            [ "type", `String "string"
            ; "anyOf", `List [ `Assoc [ "type", `String "string" ] ]
            ])
    ; S.Unsafe.of_yojson
        (`Assoc
            [ "type", `String "string"
            ; "anyOf", `List [ `Assoc [ "type", `String "string" ]; S.to_yojson S.null ]
            ])
    ]
    ~f:(fun schema ->
      let nullable = S.nullable schema in
      check nullable ~accept:[ `Null; `String "x" ] ~reject:[ `Int 1 ];
      assert (S.equal nullable (S.nullable nullable)))
;;

let%expect_test "metadata and examples do not change constraints" =
  let schema =
    S.string ()
    |> S.with_openapi ~schema_name:"Identifier" ~description:"HTTP"
    |> S.with_title "Identifier"
    |> S.with_description "Schema"
    |> S.with_deprecated true
    |> S.with_read_only true
    |> S.with_write_only false
    |> S.with_examples ~encode:(fun value -> `String value) [ "abc" ]
  in
  print schema;
  [%expect
    {| {"examples":["abc"],"writeOnly":false,"readOnly":true,"deprecated":true,"description":"Schema","title":"Identifier","type":"string"} |}];
  assert (String.equal (S.description schema) "HTTP");
  assert (Option.equal String.equal (S.schema_name schema) (Some "Identifier"));
  check schema ~accept:[ `String "anything" ] ~reject:[ `Int 1 ];
  check
    (S.never |> S.with_title "Never" |> S.with_examples ~encode:Fn.id [])
    ~accept:[]
    ~reject:[ `Null ];
  print_error (fun () -> S.with_examples ~encode:Fn.id [ `Float Float.nan ] S.any);
  [%expect {| JSON value must contain only finite floats |}]
;;

let%test_unit "constraint modifiers preserve description fallback and explicit overrides" =
  let original = S.string () |> S.with_description "Original" in
  let constrained = S.with_const ~encode:(fun value -> `String value) "x" original in
  assert (String.equal (S.description constrained) "Original");
  assert (
    String.equal (S.description (S.with_description "Updated" constrained)) "Updated");
  let overridden =
    original
    |> S.with_openapi ~description:"HTTP"
    |> S.with_const ~encode:(fun value -> `String value) "x"
  in
  assert (String.equal (S.description (S.with_description "Updated" overridden)) "HTTP");
  let dictionary =
    S.dictionary ~values:(S.integer ())
    |> S.with_description "Counters"
    |> S.with_dictionary_constraints ~min_properties:1
  in
  assert (String.equal (S.description dictionary) "Counters")
;;

let%expect_test "discriminator is explicit OpenAPI metadata" =
  let branch name kind =
    local
      name
      (S.object_
         ~properties:[ "kind", S.pack (S.string ~enum:[ kind ] ()) ]
         ~required:[ "kind" ]
         ())
  in
  let schema =
    S.one_of [ branch "Cat" "cat"; branch "Dog" "dog" ]
    |> S.with_discriminator
         ~property_name:"kind"
         ~mapping:[ "cat", "#/$defs/Cat"; "dog", "#/$defs/Dog" ]
  in
  S.to_yojson schema |> member "discriminator" |> print_json;
  [%expect
    {| {"propertyName":"kind","mapping":{"cat":"#/$defs/Cat","dog":"#/$defs/Dog"}} |}];
  check
    schema
    ~accept:[ `Assoc [ "kind", `String "cat" ]; `Assoc [ "kind", `String "dog" ] ]
    ~reject:[ `Assoc []; `Assoc [ "kind", `String "bird" ] ];
  print_error (fun () -> S.with_discriminator ~property_name:"kind" (S.string ()));
  [%expect {| discriminator requires allOf, anyOf or oneOf |}];
  print_error (fun () ->
    S.with_discriminator
      ~property_name:"kind"
      ~mapping:[ "cat", "Cat"; "cat", "Other" ]
      schema);
  [%expect {| discriminator mapping contains duplicate name cat |}]
;;

module User_id : sig
  type t

  val of_yojson : Yojson.Safe.t -> (t, string) Result.t
  val to_yojson : t -> Yojson.Safe.t
  val t_jsonschema : t S.t
end = struct
  type t = User_id of string

  let to_string (User_id value) = value
  let to_yojson value = `String (to_string value)

  let of_yojson = function
    | `String value when String.is_prefix value ~prefix:"user-" -> Ok (User_id value)
    | _ -> Error "expected a user identifier"
  ;;

  let t_jsonschema =
    S.contramap
      (S.string ~pattern:"^user-" ()
       |> S.with_openapi ~schema_name:"UserId" ~tags:[ "users" ])
      ~f:to_string
  ;;
end

let%test_unit "contramap connects an abstract type to request, response and OpenAPI" =
  let module B = Typed_endpoint_testing in
  let module E = Make (B) in
  let open E in
  let route =
    post / "identifier"
    |> documented
    |> accepts (Request.json (module User_id))
    |> returns (case `OK (Response.json (module User_id)))
    ==> fun ok () body ->
    match Request_body.read body with
    | Ok value -> respond ok value
    | Error error -> Request_body.reject error
  in
  let compiled =
    compile_exn
      [ Group.make_with_context
          ~context:(Context.return ())
          ~description:"Identifiers"
          [ route ]
      ]
  in
  let response =
    B.Client.call
      (Compiled.app compiled)
      `POST
      "/identifier"
      ~headers:[ "Content-Type", "application/json" ]
      ~body:{|"user-123"|}
  in
  assert (Int.equal (B.Response.status response) 200);
  assert (String.equal (B.Response.body response) {|"user-123"|});
  let response =
    B.Client.call
      (Compiled.app compiled)
      `POST
      "/identifier"
      ~headers:[ "Content-Type", "application/json" ]
      ~body:{|"other"|}
  in
  assert (Int.equal (B.Response.status response) 400);
  let schema =
    Compiled.openapi compiled
    |> member "components"
    |> member "schemas"
    |> member "UserId"
  in
  assert (Yojson.Safe.equal schema (S.to_yojson User_id.t_jsonschema));
  assert (List.equal String.equal (S.tags User_id.t_jsonschema) [ "users" ]);
  let composed = S.all_of [ User_id.t_jsonschema; User_id.t_jsonschema ] in
  assert (Option.is_none (S.schema_name composed));
  let constrained =
    S.with_const
      ~encode:User_id.to_yojson
      (User_id.of_yojson (`String "user-123") |> Result.ok_or_failwith)
      User_id.t_jsonschema
  in
  assert (Option.equal String.equal (S.schema_name constrained) (Some "UserId"))
;;

let%test_unit "OpenAPI traverses new schema positions and preserves literal data" =
  let module B = Typed_endpoint_testing in
  let module E = Make (B) in
  let open E in
  let value =
    S.object_
      ~properties:[ "name", S.pack (S.string ()) ]
      ~required:[ "name" ]
      ~additional_properties:S.Deny
      ()
    |> S.with_openapi ~schema_name:"Value"
  in
  let objects =
    S.object_
      ~pattern_properties:[ "^value", S.pack value ]
      ~dependent_schemas:[ "trigger", S.pack value ]
      ()
  in
  let arrays =
    S.list ~prefix_items:[ value ] ~items:value ~contains:value () |> S.as_json
  in
  let complement = S.not_ value in
  let opaque = S.to_yojson value in
  let literals =
    S.any
    |> S.with_const ~encode:Fn.id opaque
    |> S.with_enum ~encode:Fn.id [ opaque ]
    |> S.with_examples ~encode:Fn.id [ opaque ]
  in
  let discriminated =
    S.one_of [ value ]
    |> S.with_discriminator
         ~property_name:"name"
         ~mapping:[ "value", "#/components/schemas/Value" ]
  in
  let route path schema =
    let module Payload = struct
      type t = Yojson.Safe.t

      let t_jsonschema = schema
      let to_yojson = Fn.id
    end
    in
    get / path
    |> documented
    |> accepts Request.empty
    |> returns (case `OK (Response.json (module Payload)))
    ==> fun ok () () -> respond ok `Null
  in
  let compiled =
    compile_exn
      [ Group.make_with_context
          ~context:(Context.return ())
          ~description:"Schemas"
          [ route "value" value
          ; route "objects" objects
          ; route "arrays" arrays
          ; route "complement" complement
          ; route "literals" literals
          ; route "discriminated" discriminated
          ]
      ]
  in
  let doc = Compiled.openapi compiled in
  let payload path =
    doc
    |> member "paths"
    |> member path
    |> member "get"
    |> member "responses"
    |> member "200"
    |> member "content"
    |> member "application/json"
    |> member "schema"
  in
  let reference = `Assoc [ "$ref", `String "#/components/schemas/Value" ] in
  let normalized_objects = payload "/objects" in
  assert (
    Yojson.Safe.equal
      (member "patternProperties" normalized_objects |> member "^value")
      reference);
  assert (
    Yojson.Safe.equal
      (member "dependentSchemas" normalized_objects |> member "trigger")
      reference);
  let normalized_arrays = payload "/arrays" in
  List.iter [ "items"; "contains" ] ~f:(fun name ->
    assert (Yojson.Safe.equal (member name normalized_arrays) reference));
  assert (Poly.equal (member "prefixItems" normalized_arrays) (`List [ reference ]));
  assert (Yojson.Safe.equal (payload "/complement" |> member "not") reference);
  let normalized_literals = payload "/literals" in
  assert (Poly.equal (member "examples" normalized_literals) (`List [ opaque ]));
  let branches = member "allOf" normalized_literals |> Yojson.Safe.Util.to_list in
  assert (Poly.equal (List.last_exn branches |> member "enum") (`List [ opaque ]));
  assert (
    Yojson.Safe.equal
      (List.hd_exn branches
       |> member "allOf"
       |> Yojson.Safe.Util.to_list
       |> List.last_exn
       |> member "const")
      opaque);
  let normalized_discriminator = payload "/discriminated" in
  assert (Poly.equal (member "oneOf" normalized_discriminator) (`List [ reference ]));
  assert (
    Yojson.Safe.equal
      (member "discriminator" normalized_discriminator)
      (S.to_yojson discriminated |> member "discriminator"));
  let samples =
    [ `Null
    ; `Int 1
    ; `List []
    ; `List [ `Assoc [ "name", `String "x" ] ]
    ; `List [ `Assoc [ "name", `Int 1 ] ]
    ; `Assoc []
    ; `Assoc [ "value", `Assoc [ "name", `String "x" ] ]
    ; `Assoc [ "value", `Assoc [ "name", `Int 1 ] ]
    ; `Assoc [ "trigger", `Bool true ]
    ]
  in
  List.iter
    [ objects, normalized_objects
    ; arrays, normalized_arrays
    ; complement, payload "/complement"
    ]
    ~f:(fun (original, normalized) ->
      List.iter samples ~f:(fun sample ->
        let valid schema =
          Contract_test_support.validate ~document:doc ~schema sample |> Result.is_ok
        in
        assert (Bool.equal (valid (S.to_yojson original)) (valid normalized))))
;;
