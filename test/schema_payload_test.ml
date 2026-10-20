open! Base
open Typed_endpoint
module B = Typed_endpoint_testing
module E = Make (B)
open E

module Generated = struct
  type t = { message : string } [@@deriving yojson, jsonschema]
end

module Generated_request = struct
  type t = Generated.t [@@deriving of_yojson, jsonschema]
end

module Generated_response = struct
  type t = Generated.t [@@deriving to_yojson, jsonschema]
end

module Described = struct
  type t = { message : string }
  [@@jsonschema.description "Generated description"] [@@deriving yojson, jsonschema]
end

let member = Yojson.Safe.Util.member
let print json = Stdlib.print_endline (Yojson.Safe.to_string json)

let echo path payload response =
  post / path |> documented |> accepts payload |> returns (case `OK response)
  ==> fun ok () body ->
  match Request_body.read body with
  | Ok value -> respond ok value
  | Error error -> Request_body.reject error
;;

let compiled =
  compile_exn
    [ Group.make_with_context
        ~context:(Context.return ())
        ~description:"Generated payloads"
        [ echo
            "plain"
            (Request.json (module Generated_request))
            (Response.json (module Generated_response))
        ; echo
            "described"
            (Request.json (module Described))
            (Response.json (module Described))
        ]
    ]
;;

let operation path =
  Compiled.openapi compiled |> member "paths" |> member path |> member "post"
;;

let request operation = operation |> member "requestBody"
let response operation = operation |> member "responses" |> member "200"

let schema value =
  value |> member "content" |> member "application/json" |> member "schema"
;;

let%expect_test "generated schemas need no additional payload declarations" =
  request (operation "/plain") |> member "description" |> print;
  [%expect {| "" |}];
  response (operation "/plain") |> member "description" |> print;
  [%expect {| "" |}];
  request (operation "/described") |> member "description" |> print;
  [%expect {| "Generated description" |}];
  response (operation "/described") |> member "description" |> print;
  [%expect {| "Generated description" |}]
;;

let%test_unit "generated codecs and schemas share the request and response wire shape" =
  let operation = operation "/plain" in
  let expected = Json_schema.to_yojson Generated.t_jsonschema in
  assert (Yojson.Safe.equal expected (schema (request operation)));
  assert (Yojson.Safe.equal expected (schema (response operation)));
  let send body =
    B.Client.call
      (Compiled.app compiled)
      ~headers:[ "Content-Type", "application/json" ]
      ~body
      `POST
      "/plain"
  in
  let success = send {|{"message":"hello"}|} in
  assert (Int.equal (B.Response.status success) 200);
  assert (String.equal (B.Response.body success) {|{"message":"hello"}|});
  let failure = send {|{"message":42}|} in
  assert (Int.equal (B.Response.status failure) 400);
  let error = Yojson.Safe.from_string (B.Response.body failure) in
  assert (Yojson.Safe.equal (member "code" error) (`String "invalid_body"))
;;

let%test_unit "OpenAPI documentation preserves the schema and composes immutably" =
  let original = Described.t_jsonschema in
  let decorated =
    original
    |> Json_schema.with_openapi ~schema_name:"Message" ~tags:[ "messages" ]
    |> Json_schema.with_openapi ~description:"HTTP description"
    |> Json_schema.with_extension_exn ~name:"x-domain" ~value:(`String "message")
  in
  assert (Option.is_none (Json_schema.schema_name original));
  assert (List.is_empty (Json_schema.tags original));
  assert (String.equal (Json_schema.description original) "Generated description");
  assert (Option.equal String.equal (Json_schema.schema_name decorated) (Some "Message"));
  assert (List.equal String.equal (Json_schema.tags decorated) [ "messages" ]);
  assert (String.equal (Json_schema.description decorated) "HTTP description");
  let cleared = Json_schema.with_openapi ~description:"" ~tags:[] decorated in
  assert (String.is_empty (Json_schema.description cleared));
  assert (List.is_empty (Json_schema.tags cleared));
  assert (Option.equal String.equal (Json_schema.schema_name cleared) (Some "Message"));
  assert (Json_schema.equal decorated cleared);
  assert (
    Yojson.Safe.equal
      (Json_schema.to_yojson decorated)
      (Json_schema.to_yojson
         (Json_schema.with_extension_exn
            ~name:"x-domain"
            ~value:(`String "message")
            original)))
;;
