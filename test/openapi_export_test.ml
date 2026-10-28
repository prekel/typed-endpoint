open! Base
open Typed_endpoint
module E = Make (Typed_endpoint_testing)

let export ?(additional_routes = []) raw =
  let module P = struct
    type t = Yojson.Safe.t

    let t_jsonschema : t Json_schema.t =
      Json_schema.Unsafe.of_yojson (Yojson.Safe.from_string raw)
      |> Json_schema.with_openapi ~schema_name:"Payload"
    ;;

    let to_yojson = Fn.id
  end
  in
  let open E in
  let route =
    get / "export"
    |> documented
    |> accepts Request.empty
    |> returns (case `OK (Response.json (module P)))
    ==> fun ok () () -> respond ok `Null
  in
  let c =
    compile_exn
      [ Group.make_with_context ~context:(Context.return ()) (route :: additional_routes)
      ]
  in
  E.Compiled.export_openapi ~spec_version:Openapi.Spec_version.V3_0_3 c
;;

let print_schema = function
  | Error errors ->
    List.iter errors ~f:(fun e -> Stdlib.print_endline (Openapi.Export_error.to_string e))
  | Ok doc ->
    Stdlib.print_endline
      (Yojson.Safe.to_string
         Yojson.Safe.Util.(
           doc |> member "components" |> member "schemas" |> member "Payload"))
;;

let%expect_test "nullable enum retains null restriction" =
  print_schema (export {|{"type":["string","null"],"enum":["ok"]}|});
  [%expect {| {"nullable":true,"type":"string","enum":["ok"]} |}]
;;

let%expect_test "bounds and const lower without changing literals" =
  print_schema
    (export
       {|{"type":"integer","exclusiveMinimum":2,"default":3,"example":{"const":"literal"}}|});
  [%expect
    {| {"exclusiveMinimum":true,"minimum":2,"type":"integer","default":3,"example":{"const":"literal"}} |}];
  print_schema (export {|{"const":"ok"}|});
  [%expect {| {"enum":["ok"]} |}]
;;

let%expect_test "unsupported constraints return their exact schema location" =
  print_schema (export {|{"type":"array","contains":{"type":"string"}}|});
  [%expect
    {| #/components/schemas/Payload/contains: unsupported OpenAPI 3.0.3 schema keyword contains |}]
;;

let%expect_test
    "local definitions become components and reference siblings are intersections"
  =
  match
    export
      {|{"$id":"urn:payload","$defs":{"Value":{"type":"string"}},"$ref":"#/$defs/Value","description":"Use"}|}
  with
  | Error errors ->
    List.iter errors ~f:(fun e -> Stdlib.print_endline (Openapi.Export_error.to_string e))
  | Ok doc ->
    let schemas =
      Yojson.Safe.Util.(doc |> member "components" |> member "schemas" |> to_assoc)
    in
    assert (List.length schemas = 2);
    let p = List.Assoc.find_exn schemas "Payload" ~equal:String.equal in
    (match Yojson.Safe.Util.member "allOf" p with
     | `List [ _; _ ] -> ()
     | _ -> assert false);
    let other = List.find_exn schemas ~f:(fun (k, _) -> not (String.equal k "Payload")) in
    assert (Yojson.Safe.equal (snd other) (`Assoc [ "type", `String "string" ]));
    Stdlib.print_endline "resolved";
    [%expect {| resolved |}]
;;

let%expect_test "null-only types preserve impossible enum intersections" =
  print_schema (export {|{"type":"null","enum":["no"]}|});
  [%expect {| {"not":{}} |}]
;;

let%expect_test "security scope names are opaque data" =
  let open E in
  let scheme =
    Security.Scheme.oauth2_implicit
      ~name:"oauth"
      ~authorization_url:"https://example.test/authorize"
      ~scopes:[ "schema", "Read schemas" ]
      ()
  in
  let context =
    Guard.v
      ~security:[ Security.require ~scopes:[ "schema" ] scheme ]
      ~status:`Forbidden
      ~response:(Response.empty ())
      ~check:(fun _ -> Ok ())
      ()
  in
  let route =
    get / "protected"
    |> documented
    |> accepts Request.empty
    |> returns (case `OK (Response.empty ()))
    ==> fun ok () () -> respond ok ()
  in
  let c = compile_exn [ Group.make_with_context ~context [ route ] ] in
  match Compiled.export_openapi ~spec_version:Openapi.Spec_version.V3_0_3 c with
  | Error _ -> assert false
  | Ok document ->
    Stdlib.print_endline
      Yojson.Safe.Util.(
        document
        |> member "components"
        |> member "securitySchemes"
        |> member "oauth"
        |> member "flows"
        |> member "implicit"
        |> member "scopes"
        |> member "schema"
        |> to_string);
    [%expect {| Read schemas |}]
;;

let%expect_test "const and enum retain JSON literal equality semantics" =
  print_schema (export {|{"const":{"a":1,"b":2},"enum":[{"b":2,"a":1}]}|});
  [%expect {| {"allOf":[{"enum":[{"b":2,"a":1}]},{"enum":[{"a":1,"b":2}]}]} |}];
  print_schema (export {|{"const":1,"enum":[1.0]}|});
  [%expect {| {"allOf":[{"enum":[1.0]},{"enum":[1]}]} |}]
;;

let%expect_test "bundled definitions never overwrite user components" =
  let reserved =
    "Export_"
    ^ Stdlib.Digest.to_hex
        (Stdlib.Digest.string "#/components/schemas/Payload/$defs/Value")
  in
  let module P = struct
    type t = int

    let t_jsonschema =
      Json_schema.integer () |> Json_schema.with_openapi ~schema_name:reserved
    ;;

    let to_yojson x = `Int x
  end
  in
  let open E in
  let route =
    get / "reserved"
    |> documented
    |> accepts Request.empty
    |> returns (case `OK (Response.json (module P)))
    ==> fun ok () () -> respond ok 0
  in
  print_schema
    (export
       ~additional_routes:[ route ]
       {|{"$id":"urn:payload","$defs":{"Value":{"type":"string"}},"$ref":"#/$defs/Value"}|});
  [%expect
    {| #/components/schemas/Payload/$defs/Value: generated component name collides with an existing component |}]
;;
