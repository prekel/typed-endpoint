open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
open Endpoint
open Dsl

module Item = struct
  type t =
    { id : int
    ; name : string
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~schema_name:"Item" ~description:"An item" ()
  ;;

  let of_yojson = of_yojson
end

module Error_payload = struct
  type t =
    { kind : string
    ; message : string
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:t_jsonschema
      ~schema_name:"RequestError"
      ~description:"A request error"
      ()
  ;;
end

let error_kind : Decode_error.t -> string = function
  | Invalid_parameter _ -> "invalid_parameter"
  | Missing_parameter _ -> "missing_parameter"
  | Invalid_json _ -> "invalid_json"
  | Invalid_body _ -> "invalid_body"
  | Unsupported_media_type _ -> "unsupported_media_type"
  | Body_too_large _ -> "body_too_large"
;;

let error_message : Decode_error.t -> string = function
  | Invalid_parameter { error; _ } | Invalid_json { error } | Invalid_body { error } ->
    error
  | Missing_parameter { name; _ } -> "missing " ^ name
  | Unsupported_media_type { actual; _ } -> Option.value actual ~default:"missing"
  | Body_too_large { max_bytes } -> Int.to_string max_bytes
;;

let decode_error =
  Decode_error_response.json
    ~payload:(module Error_payload)
    ~map:(fun error ->
      Error_payload.{ kind = error_kind error; message = error_message error })
;;

let group ?decode_error routes =
  Group.v ?decode_error ~metadata:(Operation_metadata.v ~description:"Test API" ()) routes
;;

let echo_route ?(max_body_bytes = 64) () =
  make
    ~meth:B.post
    ~operation_id:"echoItem"
    ~path:(s "items" /? nil)
    ~request:(Request.json ~max_body_bytes (module Item))
    ~responses:(ok (Response.json (module Item)))
  @@ fun _request item -> B.return (OK item)
;;

let call app ?(headers = []) ?(body = "") meth target =
  Typed_endpoint_testing.Request.v ~headers ~body ~meth ~target ()
  |> Typed_endpoint_testing.dispatch app
;;

let%expect_test "request bodies enforce media type, decode errors, and size limit" =
  let compiled = compile_exn [ group ~decode_error [ echo_route () ] ] in
  let app = Compiled.app compiled in
  let request content_type body =
    call app ~headers:[ "content-type", content_type ] ~body `POST "/items"
  in
  let cases =
    [ request "application/vnd.test+json; charset=utf-8" {|{"id":1,"name":"ok"}|}
    ; request "text/plain" {|{"id":1,"name":"wrong"}|}
    ; request "application/json" "{"
    ; request "application/json" (String.make 65 'x')
    ]
  in
  List.iter cases ~f:(fun response ->
    Stdlib.Printf.printf
      "%d %s\n"
      (Typed_endpoint_testing.Response.status response)
      (Typed_endpoint_testing.Response.body response));
  [%expect
    {|
    200 {"id":1,"name":"ok"}
    415 {"kind":"unsupported_media_type","message":"text/plain"}
    400 {"kind":"invalid_json","message":"Line 1, bytes 0-1:\nUnexpected end of input"}
    413 {"kind":"body_too_large","message":"64"}
    |}]
;;

let%expect_test "named schemas are components and operations use references" =
  let document =
    compile_exn [ group ~decode_error [ echo_route () ] ] |> Compiled.openapi
  in
  let open Yojson.Safe.Util in
  let schema = document |> member "components" |> member "schemas" |> member "Item" in
  let request_ref =
    document
    |> member "paths"
    |> member "/items"
    |> member "post"
    |> member "requestBody"
    |> member "content"
    |> member "application/json"
    |> member "schema"
    |> member "$ref"
    |> to_string
  in
  Stdlib.Printf.printf
    "component=%b ref=%s"
    (not (Yojson.Safe.equal schema `Null))
    request_ref;
  [%expect {| component=true ref=#/components/schemas/Item |}]
;;

let%expect_test "OpenAPI declares every automatic body error status" =
  let document =
    compile_exn [ group ~decode_error [ echo_route () ] ] |> Compiled.openapi
  in
  let open Yojson.Safe.Util in
  let responses =
    document |> member "paths" |> member "/items" |> member "post" |> member "responses"
  in
  List.iter [ "400"; "413"; "415" ] ~f:(fun status ->
    Stdlib.Printf.printf
      "%s=%b "
      status
      (not (Yojson.Safe.equal (responses |> member status) `Null)));
  [%expect {| 400=true 413=true 415=true |}]
;;

let bearer =
  Security.Scheme.http_bearer
    ~name:"bearerAuth"
    ~bearer_format:"JWT"
    ~description:"Bearer token"
    ()
;;

let api_key =
  Security.Scheme.api_key
    ~name:"apiKey"
    ~parameter:"x-api-key"
    ~location:`Header
    ~description:"API key"
    ()
;;

let secured_route =
  let guard =
    Guard.v
      ~security:[ Security.require bearer; Security.require api_key ]
      ~status:`Unauthorized
      ~response:(Response.json (module Error_payload))
      ~check:(fun _request -> B.return (Ok ()))
      ()
  in
  make_with
    ~context:guard
    ~meth:B.get
    ~path:(s "secure" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"OK" ()))
  @@ fun () () -> B.return (OK "ok")
;;

let%expect_test "guard security is rendered as OR alternatives" =
  let document = compile_exn [ group [ secured_route ] ] |> Compiled.openapi in
  let open Yojson.Safe.Util in
  let security =
    document |> member "paths" |> member "/secure" |> member "get" |> member "security"
  in
  let schemes = document |> member "components" |> member "securitySchemes" in
  Stdlib.Printf.printf
    "alternatives=%d bearer=%b api_key=%b"
    (security |> to_list |> List.length)
    (not (Yojson.Safe.equal (schemes |> member "bearerAuth") `Null))
    (not (Yojson.Safe.equal (schemes |> member "apiKey") `Null));
  [%expect {| alternatives=2 bearer=true api_key=true |}]
;;

module Conflicting_item = struct
  type t = string [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~schema_name:"Item" ~description:"Wrong item" ()
  ;;
end

let conflict_route =
  make
    ~meth:B.get
    ~path:(s "conflict" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.json (module Conflicting_item)))
  @@ fun _request () -> B.return (OK "conflict")
;;

let%expect_test "conflicting component schemas are rejected" =
  (match compile [ group ~decode_error [ echo_route (); conflict_route ] ] with
   | Ok _ -> Stdlib.print_endline "unexpected success"
   | Error errors ->
     List.iter errors ~f:(fun error ->
       Stdlib.print_endline (Compile_error.to_string error)));
  [%expect {| conflicting OpenAPI schema: Item |}]
;;

let print_compile_errors groups =
  match compile groups with
  | Ok _ -> Stdlib.print_endline "unexpected success"
  | Error errors ->
    List.iter errors ~f:(fun error ->
      Stdlib.print_endline (Compile_error.to_string error))
;;

let%expect_test "invalid body limits are rejected" =
  print_compile_errors [ group ~decode_error [ echo_route ~max_body_bytes:0 () ] ];
  [%expect {| invalid body limit 0: post /items |}]
;;

let%expect_test "unknown OAuth scopes are rejected" =
  let oauth =
    Security.Scheme.oauth2_implicit
      ~name:"oauth"
      ~authorization_url:"https://example.test/authorize"
      ~scopes:[ "read", "Read access" ]
      ~description:"OAuth"
      ()
  in
  let guard =
    Guard.v
      ~security:[ Security.require ~scopes:[ "write" ] oauth ]
      ~status:`Unauthorized
      ~response:(Response.json (module Error_payload))
      ~check:(fun _request -> B.return (Ok ()))
      ()
  in
  let route =
    make_with
      ~context:guard
      ~meth:B.get
      ~path:(s "scope" /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"OK" ()))
    @@ fun () () -> B.return (OK "ok")
  in
  print_compile_errors [ group [ route ] ];
  [%expect {| invalid security scope write for scheme oauth |}]
;;

let%expect_test "conflicting security scheme definitions are rejected" =
  let first = Security.Scheme.http_bearer ~name:"auth" ~description:"Bearer" () in
  let second =
    Security.Scheme.api_key
      ~name:"auth"
      ~parameter:"x-api-key"
      ~location:`Header
      ~description:"API key"
      ()
  in
  let guard scheme =
    Guard.v
      ~security:[ Security.require scheme ]
      ~status:`Unauthorized
      ~response:(Response.json (module Error_payload))
      ~check:(fun _request -> B.return (Ok ()))
      ()
  in
  let route =
    make_with
      ~context:(Context.both (guard first) (guard second))
      ~meth:B.get
      ~path:(s "scheme-conflict" /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"OK" ()))
    @@ fun ((), ()) () -> B.return (OK "ok")
  in
  print_compile_errors [ group [ route ] ];
  [%expect {| conflicting security scheme: auth |}]
;;

let%expect_test "OpenAPI rendering is deterministic and configurable" =
  let compiled = compile_exn [ group ~decode_error [ echo_route (); secured_route ] ] in
  let config =
    Openapi.Config.v
      ~title:"Example"
      ~version:"2.0.0"
      ~servers:[ Openapi.Server.v ~url:"https://api.example.test" () ]
      ()
  in
  let first = Compiled.openapi ~config compiled in
  let second = Compiled.openapi ~config compiled in
  let open Yojson.Safe.Util in
  Stdlib.Printf.printf
    "equal=%b title=%s server=%s"
    (Yojson.Safe.equal first second)
    (first |> member "info" |> member "title" |> to_string)
    (first |> member "servers" |> index 0 |> member "url" |> to_string);
  [%expect {| equal=true title=Example server=https://api.example.test |}]
;;
