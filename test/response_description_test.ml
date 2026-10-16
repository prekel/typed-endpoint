open! Base
open Typed_endpoint
module B = Typed_endpoint_testing
module E = Make (B)
open E

let member = Yojson.Safe.Util.member
let print json = Stdlib.print_endline (Yojson.Safe.to_string json)

module Payload = struct
  type t = { message : string } [@@deriving yojson, jsonschema]

  let metadata =
    Metadata.v ~schema:t_jsonschema ~schema_name:"Payload" ~description:"DTO response" ()
  ;;
end

let value = Payload.{ message = "same body" }
let header = Header.required "X-Mode" (Header.string ~description:"Mode" ())

let route ?description path =
  get / path
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.json ?description (module Payload)))
  ==> fun ok () () -> respond ok value
;;

let header_route ?description path =
  get / path
  |> documented
  |> accepts Request.empty
  |> returns
       (case
          `Not_found
          (Response.with_header header (Response.json ?description (module Payload))))
  ==> fun not_found () () -> respond not_found ("marker", value)
;;

let compile routes =
  compile_exn
    [ Group.make_with_context
        ~context:(Context.return ())
        ~description:"Descriptions"
        routes
    ]
;;

let response doc path meth code =
  doc |> member "paths" |> member path |> member meth |> member "responses" |> member code
;;

let description doc path code = response doc path "get" code |> member "description"

let schema response =
  response |> member "content" |> member "application/json" |> member "schema"
;;

let wire response =
  B.Response.status response, B.Response.headers response, B.Response.body response
;;

let local =
  compile
    [ route "default"
    ; route ~description:"Pet not found" "explicit"
    ; route ~description:"" "empty"
    ; header_route "header-default"
    ; header_route ~description:"Missing with header" "header-explicit"
    ]
;;

let doc = Compiled.openapi local

let%expect_test "JSON responses inherit DTO descriptions unless explicitly overridden" =
  description doc "/default" "200" |> print;
  [%expect {| "DTO response" |}];
  description doc "/explicit" "200" |> print;
  [%expect {| "Pet not found" |}];
  description doc "/empty" "200" |> print;
  [%expect {| "" |}];
  description doc "/header-explicit" "404" |> print;
  [%expect {| "Missing with header" |}]
;;

let%test_unit
    "local descriptions preserve the DTO schema, component identity, headers and wire"
  =
  let schemas =
    doc |> member "components" |> member "schemas" |> Yojson.Safe.Util.to_assoc
  in
  assert (List.equal String.equal (List.map schemas ~f:fst) [ "Payload" ]);
  assert (
    Yojson.Safe.equal
      (List.Assoc.find_exn schemas "Payload" ~equal:String.equal)
      (Json_schema.to_yojson Payload.t_jsonschema));
  let expected = schema (response doc "/default" "get" "200") in
  List.iter
    [ "/explicit", "200"; "/empty", "200"; "/header-explicit", "404" ]
    ~f:(fun (path, code) ->
      assert (Yojson.Safe.equal expected (schema (response doc path "get" code))));
  assert (
    Yojson.Safe.equal
      (response doc "/header-default" "get" "404" |> member "headers")
      (response doc "/header-explicit" "get" "404" |> member "headers"));
  let send = B.Client.call (Compiled.app local) in
  List.iter [ "/explicit"; "/empty" ] ~f:(fun path ->
    assert (Poly.equal (wire (send `GET "/default")) (wire (send `GET path))));
  assert (
    Poly.equal (wire (send `GET "/header-default")) (wire (send `GET "/header-explicit")));
  assert (
    String.equal (B.Response.body (send `GET "/explicit")) {|{"message":"same body"}|});
  (* Declaring an override must not mutate metadata used by later endpoints. *)
  let later = compile [ route "later" ] |> Compiled.openapi in
  assert (Yojson.Safe.equal (description later "/later" "200") (`String "DTO response"))
;;

let policy = Decode_error_response.json ~payload:(module Payload) ~map:(fun _ -> value)

let partial =
  policy
  |> Decode_error_response.with_description (function
    | `Bad_request -> Some "Invalid request"
    | `Request_entity_too_large -> Some ""
    | _ -> None)
;;

let calls = ref 0

let documented_policy =
  policy
  |> Decode_error_response.with_description (fun status ->
    Int.incr calls;
    match status with
    | `Bad_request -> Some "Invalid request"
    | `Request_entity_too_large -> Some "Request body too large"
    | `Unsupported_media_type -> Some "Unsupported media type"
    | _ -> None)
;;

let body_route ?decode_error path =
  post / path /: arg "id" (Parameter.int ~description:"Identifier" ())
  |> documented ?decode_error
  |> accepts (Request.json ~max_body_bytes:64 (module Payload))
  |> returns (case `OK (Response.json (module Payload)))
  ==> fun _id ok () body ->
  match Request_body.read body with
  | Ok value -> respond ok value
  | Error error -> Request_body.reject error
;;

let explicit_error ?description path =
  post / path
  |> documented ~decode_error:documented_policy
  |> accepts (Request.json ~max_body_bytes:64 (module Payload))
  |> returns
       (case `OK (Response.json (module Payload))
        <|> case `Bad_request (Response.json ?description (module Payload)))
  ==> fun ok bad_request () body ->
  match Request_body.read body with
  | Error error -> Request_body.reject error
  | Ok { message = "reject" } -> respond bad_request value
  | Ok value -> respond ok value
;;

let policies =
  compile
    [ body_route ~decode_error:policy "baseline"
    ; body_route ~decode_error:partial "partial"
    ; body_route ~decode_error:documented_policy "documented"
    ; explicit_error ~description:"Explicit invalid request" "explicit-error"
    ; explicit_error ~description:"" "empty-error"
    ; explicit_error "fallback-error"
    ]
;;

let policies_doc = Compiled.openapi policies

let error_description path code =
  response policies_doc path "post" code |> member "description"
;;

let%expect_test "decode policy descriptions distinguish omission and an empty override" =
  error_description "/partial/{id}" "400" |> print;
  [%expect {| "Invalid request" |}];
  error_description "/partial/{id}" "413" |> print;
  [%expect {| "" |}];
  error_description "/partial/{id}" "415" |> print;
  [%expect {| "DTO response" |}]
;;

let%expect_test
    "automatic descriptions differ by status and explicit cases retain precedence"
  =
  error_description "/documented/{id}" "400" |> print;
  [%expect {| "Invalid request" |}];
  error_description "/documented/{id}" "413" |> print;
  [%expect {| "Request body too large" |}];
  error_description "/documented/{id}" "415" |> print;
  [%expect {| "Unsupported media type" |}];
  error_description "/explicit-error" "400" |> print;
  [%expect {| "Explicit invalid request" |}];
  error_description "/empty-error" "400" |> print;
  [%expect {| "" |}];
  error_description "/fallback-error" "400" |> print;
  [%expect {| "DTO response" |}]
;;

let%test_unit "decode documentation does not change statuses, headers, bodies or schema" =
  let send = B.Client.call (Compiled.app policies) in
  let cases =
    [ "bad", [ "content-type", "application/json" ], "{}", 400
    ; "1", [ "content-type", "application/json" ], "{", 400
    ; "1", [ "content-type", "text/plain" ], "body", 415
    ; "1", [ "content-type", "application/json" ], String.make 65 'x', 413
    ; "1", [ "content-type", "application/json" ], {|{"message":"ok"}|}, 200
    ]
  in
  let initial_calls = !calls in
  List.iter cases ~f:(fun (id, headers, body, status) ->
    let original = send ~headers ~body `POST ("/baseline/" ^ id) in
    assert (B.Response.status original = status);
    List.iter [ "documented"; "partial" ] ~f:(fun path ->
      let actual = send ~headers ~body `POST ("/" ^ path ^ "/" ^ id) in
      assert (Poly.equal (wire original) (wire actual))));
  assert (Int.equal initial_calls !calls);
  List.iter [ "400"; "413"; "415" ] ~f:(fun code ->
    assert (
      Yojson.Safe.equal
        (schema (response policies_doc "/baseline/{id}" "post" code))
        (schema (response policies_doc "/documented/{id}" "post" code))));
  List.iter [ "{"; {|{"message":"reject"}|} ] ~f:(fun body ->
    let result =
      send ~headers:[ "content-type", "application/json" ] ~body `POST "/explicit-error"
    in
    assert (B.Response.status result = 400);
    assert (String.equal (B.Response.body result) {|{"message":"same body"}|}))
;;

let%test_unit "description overrides follow endpoint group compile policy selection" =
  let named description =
    policy |> Decode_error_response.with_description (fun _ -> Some description)
  in
  let selected =
    compile_exn
      ~decode_error:(named "Compile policy")
      [ Group.make_with_context
          ~context:(Context.return ())
          ~description:"Group"
          ~decode_error:(named "Group policy")
          [ body_route ~decode_error:(named "Endpoint policy") "endpoint"
          ; body_route "group"
          ]
      ; Group.make_with_context
          ~context:(Context.return ())
          ~description:"Default"
          [ body_route "compile" ]
      ]
  in
  let doc = Compiled.openapi selected in
  List.iter
    [ "endpoint", "Endpoint policy"
    ; "group", "Group policy"
    ; "compile", "Compile policy"
    ]
    ~f:(fun (path, expected) ->
      List.iter [ "400"; "413"; "415" ] ~f:(fun code ->
        assert (
          Yojson.Safe.equal
            (response doc ("/" ^ path ^ "/{id}") "post" code |> member "description")
            (`String expected))));
  let reset =
    documented_policy |> Decode_error_response.with_description (fun _ -> None)
  in
  let doc = compile [ body_route ~decode_error:reset "reset" ] |> Compiled.openapi in
  assert (
    Yojson.Safe.equal
      (response doc "/reset/{id}" "post" "413" |> member "description")
      (`String "DTO response"))
;;
