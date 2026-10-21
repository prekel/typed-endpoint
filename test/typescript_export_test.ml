open! Base
open Typed_endpoint
module S = Json_schema

let export schema = S.to_yojson_for_typescript schema |> Result.ok_or_failwith
let print json = Stdlib.print_endline (Yojson.Safe.to_string json)
let member = Yojson.Safe.Util.member
let imported json = S.Unsafe.of_yojson (Yojson.Safe.from_string json)

module Tuple = struct
  type t = int * string [@@deriving yojson, jsonschema]
end

module Result_payload = struct
  type t = (int, string) Result.t [@@deriving jsonschema]
  type qualified = (int, string) Stdlib.result [@@deriving jsonschema]
end

let%expect_test "result schemas retain success and error payload types" =
  assert (S.equal Result_payload.t_jsonschema Result_payload.qualified_jsonschema);
  print (export Result_payload.t_jsonschema);
  [%expect
    {| {"anyOf":[{"type":"array","items":[{"const":"Error"},{"type":"string"}],"additionalItems":false,"minItems":2,"maxItems":2},{"type":"array","items":[{"const":"Ok"},{"type":"integer"}],"additionalItems":false,"minItems":2,"maxItems":2}]} |}]
;;

let%expect_test "TypeScript tuples use items without changing the ordinary schema" =
  print (export Tuple.t_jsonschema);
  [%expect
    {| {"type":"array","items":[{"type":"integer"},{"type":"string"}],"additionalItems":false,"minItems":2,"maxItems":2} |}];
  print (S.to_yojson Tuple.t_jsonschema);
  [%expect
    {| {"type":"array","prefixItems":[{"type":"integer"},{"type":"string"}],"unevaluatedItems":false,"minItems":2,"maxItems":2} |}]
;;

let%expect_test "boolean roots and referenced definitions retain their meaning" =
  print (export S.any);
  [%expect {| {"tsType":"unknown"} |}];
  print (export S.never);
  [%expect {| {"not":{},"tsType":"never"} |}];
  let schema =
    S.Deriver.root_ref ~root:"Nothing" ~definitions:[ "Nothing", S.pack S.never ]
  in
  print (export schema);
  [%expect
    {| {"$ref":"#/definitions/Nothing","definitions":{"Nothing":{"not":{},"tsType":"never"}}} |}]
;;

let%expect_test "resource definitions with identical names are bundled distinctly" =
  let resource id value =
    S.Deriver.root_ref ~root:"node" ~definitions:[ "node", S.pack value ]
    |> S.Deriver.with_id id
  in
  let schema =
    S.object_
      ~properties:
        [ "left", S.pack (resource "urn:test:left" (S.string ()))
        ; "right", S.pack (resource "urn:test:right" (S.integer ()))
        ]
      ()
  in
  let output = export schema in
  output |> member "properties" |> print;
  [%expect
    {| {"left":{"$ref":"#/definitions/node"},"right":{"$ref":"#/definitions/node_2"}} |}];
  output |> member "definitions" |> print;
  [%expect {| {"node":{"type":"string"},"node_2":{"type":"integer"}} |}];
  assert (Yojson.Safe.equal output (export schema))
;;

let%expect_test "JSON pointer escapes and URI fragments resolve before renaming" =
  let schema =
    imported {|{"$defs":{"a/b~c":{"type":"integer"}},"$ref":"#/$defs/a~1%62~0c"}|}
  in
  print (export schema);
  [%expect
    {| {"$ref":"#/definitions/a_b_c","definitions":{"a_b_c":{"type":"integer"}}} |}]
;;

let%expect_test "empty imported prefixes retain homogeneous array items" =
  let schema = imported {|{"type":"array","prefixItems":[],"items":{"type":"string"}}|} in
  print (export schema);
  [%expect {| {"type":"array","items":{"type":"string"}} |}]
;;

let%test_unit "schema-looking literals and annotations are not traversed" =
  let literal =
    Yojson.Safe.from_string
      {|{"$id":"relative","$ref":"external","prefixItems":[1],"$defs":{"node":42}}|}
  in
  let schema =
    S.with_const ~encode:Fn.id literal S.any |> S.with_examples ~encode:Fn.id [ literal ]
  in
  let before = S.to_yojson schema in
  let after = export schema in
  List.iter [ "const"; "examples" ] ~f:(fun key ->
    assert (Yojson.Safe.equal (member key before) (member key after)));
  let schema =
    imported
      {|{"type":"object","properties":{"value":{"type":"integer","default":{"prefixItems":[1],"$ref":"literal"}}},"additionalProperties":false}|}
  in
  assert (Yojson.Safe.equal (S.to_yojson schema) (export schema))
;;

let%expect_test "unsupported references and resource scopes return diagnostics" =
  let diagnostic json =
    match S.to_yojson_for_typescript (imported json) with
    | Ok _ -> Stdlib.failwith "expected an export diagnostic"
    | Error message -> Stdlib.print_endline message
  in
  diagnostic {|{"$ref":"https://example.invalid/schema"}|};
  [%expect
    {| TypeScript export at #: unresolved resource https://example.invalid/schema (external references are not fetched) |}];
  diagnostic {|{"$ref":"#/$defs/missing"}|};
  [%expect {| TypeScript export at #: unresolved $ref #/$defs/missing |}];
  diagnostic {|{"$id":"relative.json","type":"string"}|};
  [%expect {| TypeScript export at #: $id must be an absolute URI without a fragment |}];
  diagnostic {|{"$dynamicRef":"#node"}|};
  [%expect {| TypeScript export at #: $dynamicRef is not supported |}];
  diagnostic {|{"$ref":"#node"}|};
  [%expect {| TypeScript export at #: unsupported $ref anchor #node |}];
  diagnostic {|{"type":"array","allOf":[],"prefixItems":[true],"unevaluatedItems":false}|};
  [%expect
    {| TypeScript export at #: unevaluatedItems with schema applicators cannot be lowered safely |}]
;;

let%test_unit "forward resource references resolve without fetching external data" =
  let schema =
    imported
      {|{"type":"object","properties":{"first":{"$ref":"urn:test:later#/$defs/value"},"second":{"$id":"urn:test:later","$defs":{"value":{"type":"integer"}},"$ref":"#/$defs/value"}}}|}
  in
  let properties = export schema |> member "properties" in
  assert (Yojson.Safe.equal (member "first" properties) (member "second" properties))
;;
