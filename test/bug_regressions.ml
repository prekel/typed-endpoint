open! Base
open Typed_endpoint
module B = Typed_endpoint_testing
module E = Make (B)
open E

let group routes =
  Group.make_with_context ~context:(Context.return ()) ~description:"Regressions" routes
;;

let text_route uri =
  uri
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Result" ()))
  ==> fun ok () () -> respond ok "ok"
;;

let invalid routes = Result.is_error (compile [ group routes ])

let%test_unit "informational responses cannot be final even without content" =
  List.iter [ 100; 101; 103; 199 ] ~f:(fun status ->
    let route =
      get / "status"
      |> documented
      |> accepts Request.empty
      |> returns (case (`Code status) (Response.empty ~description:"Empty" ()))
      ==> fun ok () () -> respond ok ()
    in
    assert (invalid [ route ]));
  List.iter [ 204; 205; 304 ] ~f:(fun status ->
    let route =
      get / "status"
      |> documented
      |> accepts Request.empty
      |> returns (case (`Code status) (Response.empty ~description:"Empty" ()))
      ==> fun ok () () -> respond ok ()
    in
    assert (Result.is_ok (compile [ group [ route ] ])))
;;

let%test_unit "paths and prefixes reject malformed static segments" =
  List.iter
    [ "a b"; "a\t"; "a\000"; "a\127"; "%"; "%1"; "%GG"; "a?b"; "a#b" ]
    ~f:(fun segment ->
      assert (invalid [ text_route (get / segment) ]);
      assert (
        Result.is_error
          (compile
             [ Group.make_with_context
                 ~prefix:[ segment ]
                 ~context:(Context.return ())
                 ~description:"Prefix"
                 [ text_route (get / "ok") ]
             ])));
  List.iter [ "a%20b"; "%7Bid%7D"; "a-b" ] ~f:(fun segment ->
    assert (Result.is_ok (compile [ group [ text_route (get / segment) ] ])))
;;

let capture_route name =
  get /: arg name (Parameter.string ~description:"Capture" ())
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Result" ()))
  ==> fun value ok () () -> respond ok value
;;

let%test_unit "capture names use the documented portable URI-template subset" =
  List.iter
    [ ""; "{id}"; "a-b"; "a b"; "a?b"; ".id"; "id."; "a..b"; "%20" ]
    ~f:(fun name -> assert (invalid [ capture_route name ]));
  List.iter [ "id"; "pet_id"; "a.b"; "123" ] ~f:(fun name ->
    assert (Result.is_ok (compile [ group [ capture_route name ] ])))
;;

let%expect_test "literal braces never become OpenAPI path parameters" =
  let template = ref "" in
  let interceptor ~route_info ~request:_ ~next =
    template := route_info.Route_info.path_template;
    next ()
  in
  let compiled =
    compile_exn
      ~interceptors:[ interceptor ]
      [ group [ text_route (get / "literal" / "{id}") ] ]
  in
  let response = B.Client.call (Compiled.app compiled) `GET "/literal/%7Bid%7D" in
  assert (B.Response.status response = 200);
  let open Yojson.Safe.Util in
  Compiled.openapi compiled
  |> member "paths"
  |> to_assoc
  |> List.map ~f:fst
  |> List.iter ~f:Stdlib.print_endline;
  [%expect {| /literal/%7Bid%7D |}];
  Stdlib.print_endline !template;
  [%expect {| /literal/%7Bid%7D |}]
;;

let%test_unit "decimal parameter and header codecs reject OCaml literals" =
  let module I = (val Parameter.int ~description:"Integer" ()) in
  let module I64 = (val Parameter.int64 ~description:"Integer" ()) in
  let module H = (val Header.int ~description:"Integer" ()) in
  let module H64 = (val Header.int64 ~description:"Integer" ()) in
  List.iter
    [ "0x10"; "0o10"; "0b10"; "1_000"; " 1"; "1 "; ""; "+"; "1.0" ]
    ~f:(fun value ->
      assert (Result.is_error (I.of_string value));
      assert (Result.is_error (I64.of_string value));
      assert (Result.is_error (H.of_string value));
      assert (Result.is_error (H64.of_string value)));
  List.iter [ "0"; "01"; "-12"; "+12" ] ~f:(fun value ->
    assert (Result.is_ok (I.of_string value));
    assert (Result.is_ok (I64.of_string value)));
  assert (Result.is_error (I.of_string "9999999999999999999999999999"));
  assert (Result.is_error (I64.of_string "9223372036854775808"))
;;

let%test_unit "floating parameters accept finite decimal mantissas and exponents" =
  let module F = (val Parameter.float ~description:"Float" ()) in
  List.iter
    [ "0x1p2"; "1_000.0"; "NaN"; "Infinity"; "1e999"; "1e"; "."; " 1.5" ]
    ~f:(fun value -> assert (Result.is_error (F.of_string value)));
  List.iter [ "1.5"; "-1e-2"; "+2E3"; ".5"; "1."; "0" ] ~f:(fun value ->
    assert (Result.is_ok (F.of_string value)))
;;

module Payload = struct
  type t = string [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~schema:t_jsonschema ~description:"String" ()
end

let json_route ?media_types () =
  post / "json"
  |> documented
  |> accepts (Request.json ?media_types (module Payload))
  |> returns (case `OK (Response.json (module Payload)))
  ==> fun ok () body ->
  let open Io.Let_syntax in
  let%bind result = Request_body.read body in
  match result with
  | Ok value -> respond ok value
  | Error error -> Request_body.reject error
;;

let%test_unit "JSON media types are explicit and shared by runtime and OpenAPI" =
  let compiled =
    compile_exn
      [ group
          [ json_route
              ~media_types:[ "application/json"; "Application/Vnd.Example+Json" ]
              ()
          ]
      ]
  in
  let app = Compiled.app compiled in
  let request content_type =
    B.Client.call
      app
      ~headers:[ "content-type", content_type ]
      ~body:{|"value"|}
      `POST
      "/json"
  in
  assert (B.Response.status (request "APPLICATION/VND.EXAMPLE+JSON; charset=utf-8") = 200);
  List.iter
    [ "application/+json"; "application/other+json"; "application/*+json" ]
    ~f:(fun value -> assert (B.Response.status (request value) = 415));
  let open Yojson.Safe.Util in
  let keys =
    Compiled.openapi compiled
    |> member "paths"
    |> member "/json"
    |> member "post"
    |> member "requestBody"
    |> member "content"
    |> to_assoc
    |> List.map ~f:fst
  in
  assert (
    List.equal String.equal keys [ "application/json"; "application/vnd.example+json" ]);
  let default_app = compile_exn [ group [ json_route () ] ] |> Compiled.app in
  assert (
    B.Response.status
      (B.Client.call
         default_app
         ~headers:[ "content-type", "application/vnd.example+json" ]
         ~body:{|"value"|}
         `POST
         "/json")
    = 415);
  List.iter
    [ []
    ; [ "application/+json" ]
    ; [ "application/*+json" ]
    ; [ "text/json" ]
    ; [ "application/foo bar+json" ]
    ; [ "application/json; charset=utf-8" ]
    ]
    ~f:(fun media_types -> assert (invalid [ json_route ~media_types () ]))
;;

let%test_unit "reserved request and response headers cannot override contracts" =
  List.iter [ "Accept"; "CONTENT-TYPE"; "authorization" ] ~f:(fun name ->
    let route =
      get / "header"
      |> header (Header.required name (Header.string ~description:"Header" ()))
      |> documented
      |> accepts Request.empty
      |> returns (case `OK (Response.empty ~description:"Empty" ()))
      ==> fun _value ok () () -> respond ok ()
    in
    assert (invalid [ route ]));
  List.iter
    [ "Content-Type"; "content-length"; "TRANSFER-ENCODING"; "Trailer"; "Connection" ]
    ~f:(fun name ->
      let route =
        get / "header"
        |> documented
        |> accepts Request.empty
        |> returns
             (case
                `OK
                (Response.empty ~description:"Empty" ()
                 |> Response.with_header
                      (Header.required name (Header.string ~description:"Header" ()))))
        ==> fun ok () () -> respond ok ("value", ())
      in
      assert (invalid [ route ]))
;;

let oauth_group authorization_url =
  let scheme =
    Security.Scheme.oauth2_implicit
      ~name:"oauth"
      ~authorization_url
      ~scopes:[]
      ~description:"OAuth"
      ()
  in
  let guard =
    Guard.v
      ~security:[ Security.require scheme ]
      ~status:`Unauthorized
      ~response:(Response.text ~description:"Error" ())
      ~check:(fun _request -> Io.return (Ok ()))
      ()
  in
  Group.make_with_context
    ~context:guard
    ~description:"OAuth"
    [ text_route (get / "oauth") ]
;;

let%test_unit "invalid OAuth URLs fail public compilation with the existing error" =
  List.iter
    [ "https://[1]/authorize"
    ; "https://host/<>"
    ; "https://host/\"authorize\""
    ; "https://host/\\authorize"
    ; "https://host/authorize#fragment"
    ; "https://host/authorize#"
    ; "https://host/?scope=<read>"
    ; "https://host/?scope=[read]"
    ; "https://host/\195\169"
    ; "https://host/\000"
    ; "https://host/authorize%"
    ; "https://host/authorize%2"
    ; "https://host/authorize%GG"
    ; "https://host/?scope=%XX"
    ; "https://host%XX/authorize"
    ; "https://user%XX@host/authorize"
    ; "https://bad<user>@host/authorize"
    ; "https://user@name@host/authorize"
    ; "https://[1:2:3:4:5:6:7]/authorize"
    ; "https://[1:2:3:4:5:6:7:8:9]/authorize"
    ; "https://[1:2:3:4:5:6:7:8::]/authorize"
    ; "https://[::1::]/authorize"
    ; "https://[:::]/authorize"
    ; "https://[12345::]/authorize"
    ; "https://[::ffff:256.0.0.1]/authorize"
    ; "https://[::ffff:192.000.2.1]/authorize"
    ; "https://[::1.2.3.4:1.2.3.4]/authorize"
    ; "https://[192.0.2.1::]/authorize"
    ; "https://[v.foo]/authorize"
    ; "https://[v1.]/authorize"
    ; "https://[v1.foo%20]/authorize"
    ; "https://[::1]suffix/authorize"
    ; "https://host:port/authorize"
    ; "https://[]/authorize"
    ; "https://[::1/authorize"
    ; "https://@/authorize"
    ; "https:///authorize"
    ; "/authorize"
    ; "ftp://host/authorize"
    ]
    ~f:(fun authorization_url ->
      match compile [ oauth_group authorization_url ] with
      | Error [ Compile_error.Invalid_security_authorization_url "oauth" ] -> ()
      | _ -> failwith ("invalid OAuth URL was accepted: " ^ authorization_url))
;;

let%test_unit "valid OAuth URL components are preserved in OpenAPI" =
  List.iter
    [ "https://example.test/authorize"
    ; "HTTP://LOCALHOST:8080/authorize"
    ; "https://example.test"
    ; "https://example.test:443/authorize"
    ; "https://example.test:/authorize"
    ; "https://192.0.2.1/authorize"
    ; "https://[::]/authorize"
    ; "https://[::1]:443/authorize"
    ; "https://[2001:db8::1]/authorize"
    ; "https://[1:2:3:4:5:6:7:8]/authorize"
    ; "https://[0:0:0:0:0:ffff:192.0.2.1]/authorize"
    ; "https://[::ffff:192.0.2.1]/authorize"
    ; "https://[v1.example:future]/authorize"
    ; "https://[Vab.example]/authorize"
    ; "https://user:password@example.test/authorize"
    ; "https://user%3Aname@example.test/authorize"
    ; "https://example.test/a%20b/%3C%3E?scope=read%20write&next=/a?b"
    ; "https://example.test/?scope=read+write"
    ; "https://example.test/authorize?"
    ; "https://example.test/authorize?state=%23fragment"
    ]
    ~f:(fun authorization_url ->
      let compiled = compile_exn [ oauth_group authorization_url ] in
      let open Yojson.Safe.Util in
      let rendered =
        Compiled.openapi compiled
        |> member "components"
        |> member "securitySchemes"
        |> member "oauth"
        |> member "flows"
        |> member "implicit"
        |> member "authorizationUrl"
        |> to_string
      in
      assert (String.equal rendered authorization_url))
;;
