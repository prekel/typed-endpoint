open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
module Io = Endpoint.Io
open Io.Let_syntax
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

let group ?decode_error routes = Group.make ?decode_error ~description:"Test API" routes

let echo_route ?(max_body_bytes = 64) () =
  make
    ~meth:B.post
    ~operation_id:"echoItem"
    ~path:(s "items" /? nil)
    ~request:(Request.json ~max_body_bytes (module Item))
    ~responses:(ok (Response.json (module Item)))
  @@ fun item -> return (OK item)
;;

let binary_route =
  make
    ~meth:B.post
    ~operation_id:"uploadBinary"
    ~path:(s "binary" /? nil)
    ~request:(Request.binary ~max_body_bytes:4 ~description:"Opaque bytes" ())
    ~responses:(ok (Response.text ~description:"Byte length" ()))
  @@ fun bytes -> return (OK (Int.to_string (String.length bytes)))
;;

let call = Typed_endpoint_testing.Client.call

let%expect_test "backend IO exposes Base monad syntax" =
  let open Io.Let_syntax in
  let computation =
    let%bind left = return 20 in
    let%map right = return 22 in
    left + right
  in
  Stdlib.Printf.printf "%d" computation;
  [%expect {| 42 |}]
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

let%expect_test "binary bodies enforce media type and render their OpenAPI schema" =
  let compiled = compile_exn [ group ~decode_error [ binary_route ] ] in
  let app = Compiled.app compiled in
  let invoke content_type body =
    call app ~headers:[ "content-type", content_type ] ~body `POST "/binary"
  in
  let open Yojson.Safe.Util in
  let schema =
    Compiled.openapi compiled
    |> member "paths"
    |> member "/binary"
    |> member "post"
    |> member "requestBody"
    |> member "content"
    |> member "application/octet-stream"
    |> member "schema"
  in
  List.iter
    [ invoke "application/octet-stream" "data"
    ; invoke "text/plain" "data"
    ; invoke "application/octet-stream" "large"
    ]
    ~f:(fun response ->
      Stdlib.Printf.printf
        "%d:%s "
        (Typed_endpoint_testing.Response.status response)
        (Typed_endpoint_testing.Response.body response));
  Stdlib.Printf.printf
    "schema=%s/%s"
    (schema |> member "type" |> to_string)
    (schema |> member "format" |> to_string);
  [%expect
    {|
    200:4 415:{"kind":"unsupported_media_type","message":"text/plain"} 413:{"kind":"body_too_large","message":"4"} schema=string/binary |}]
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

let%expect_test "a safe decode-error policy is available by default" =
  let compiled = compile_exn [ group [ echo_route () ] ] in
  let app = Compiled.app compiled in
  let unsupported =
    call app ~headers:[ "content-type", "text/plain" ] ~body:"not json" `POST "/items"
  in
  let invalid_json =
    call app ~headers:[ "content-type", "application/json" ] ~body:"{" `POST "/items"
  in
  let invalid_body =
    call
      app
      ~headers:[ "content-type", "application/json" ]
      ~body:{|{"id":"secret","name":"hidden"}|}
      `POST
      "/items"
  in
  let open Yojson.Safe.Util in
  let document = Compiled.openapi compiled in
  let schema_ref =
    document
    |> member "paths"
    |> member "/items"
    |> member "post"
    |> member "responses"
    |> member "415"
    |> member "content"
    |> member "application/json"
    |> member "schema"
    |> member "$ref"
    |> to_string
  in
  List.iter [ unsupported; invalid_json; invalid_body ] ~f:(fun response ->
    Stdlib.Printf.printf
      "%d %s\n"
      (Typed_endpoint_testing.Response.status response)
      (Typed_endpoint_testing.Response.body response));
  Stdlib.print_string schema_ref;
  [%expect
    {|
    415 {"code":"unsupported_media_type","message":"request content type is not supported"}
    400 {"code":"invalid_json","message":"request body is not valid JSON"}
    400 {"code":"invalid_body","message":"request body does not match the declared schema"}
    #/components/schemas/TypedEndpointDecodeError
    |}]
;;

let primitive_route =
  make
    ~meth:B.get
    ~path:
      (s "primitive"
       / param "id" (Parameter.int ~description:"Integer identifier" ())
       / query_req "enabled" (Parameter.bool ~description:"Whether it is enabled" ())
       /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"Decoded values" ()))
  @@ fun id enabled () -> return (OK (Int.to_string id ^ ":" ^ Bool.to_string enabled))
;;

let empty_response_route =
  make
    ~meth:B.get
    ~path:(s "empty" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.empty ~description:"No representation" ()))
  @@ fun () -> return (OK ())
;;

let%expect_test "testing client exposes representation and routing headers" =
  let app =
    compile_exn [ group [ primitive_route; empty_response_route ] ] |> Compiled.app
  in
  let text = call app `GET "/primitive/42?enabled=true" in
  let empty = call app `GET "/empty" in
  let wrong_method = call app `POST "/primitive/42?enabled=true" in
  let header response name =
    Typed_endpoint_testing.Response.header response name |> Option.value ~default:"none"
  in
  Stdlib.Printf.printf
    "text=%s empty=%s allow=%s error=%s"
    (header text "Content-Type")
    (header empty "content-type")
    (header wrong_method "ALLOW")
    (header wrong_method "content-type");
  [%expect
    {|
    text=text/plain; charset=utf-8 empty=none allow=GET error=text/plain; charset=utf-8 |}]
;;

let%expect_test "static routes take precedence over path captures" =
  let captured =
    make
      ~meth:B.get
      ~path:
        (s "priority"
         / param "value" (Parameter.string ~description:"Captured value" ())
         /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"Captured" ()))
    @@ fun value () -> return (OK ("capture:" ^ value))
  in
  let fixed =
    make
      ~meth:B.get
      ~path:(s "priority" / s "fixed" /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"Static" ()))
    @@ fun () -> return (OK "static")
  in
  let app = compile_exn [ group [ captured; fixed ] ] |> Compiled.app in
  let fixed = call app `GET "/priority/fixed" in
  let captured = call app `GET "/priority/other" in
  Stdlib.Printf.printf
    "%s %s"
    (Typed_endpoint_testing.Response.body fixed)
    (Typed_endpoint_testing.Response.body captured);
  [%expect {| static capture:other |}]
;;

let%expect_test "built-in parameter codecs drive runtime parsing and OpenAPI" =
  let module Float_parameter = (val Parameter.float ~description:"Finite number" ()) in
  let compiled = compile_exn [ group [ primitive_route ] ] in
  let app = Compiled.app compiled in
  let ok = call app `GET "/primitive/42?enabled=true" in
  let invalid = call app `GET "/primitive/nope?enabled=yes" in
  let open Yojson.Safe.Util in
  let parameters =
    Compiled.openapi compiled
    |> member "paths"
    |> member "/primitive/{id}"
    |> member "get"
    |> member "parameters"
    |> to_list
  in
  List.iter [ ok; invalid ] ~f:(fun response ->
    Stdlib.Printf.printf
      "%d %s\n"
      (Typed_endpoint_testing.Response.status response)
      (Typed_endpoint_testing.Response.body response));
  parameters
  |> List.map ~f:(fun parameter ->
    (parameter |> member "name" |> to_string)
    ^ ":"
    ^ (parameter |> member "schema" |> member "type" |> to_string))
  |> String.concat ~sep:" "
  |> Stdlib.print_string;
  Stdlib.Printf.printf
    "\nfloat:finite=%b,nan=%b,infinity=%b"
    (Result.is_ok (Float_parameter.of_string "1.5"))
    (Result.is_ok (Float_parameter.of_string "nan"))
    (Result.is_ok (Float_parameter.of_string "infinity"));
  [%expect
    {|
    200 42:true
    400 {"code":"invalid_parameter","message":"invalid path parameter id"}
    id:integer enabled:boolean
    float:finite=true,nan=false,infinity=false |}]
;;

let dependency_route =
  let context =
    let open Context.Let_syntax in
    let%map values = Context.all [ Dependency.value 20; Dependency.value 21 ]
    and final_value = Context.return 1 in
    List.fold values ~init:final_value ~f:( + )
  in
  make_with
    ~context
    ~meth:B.get
    ~path:(s "dependency" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"Injected value" ()))
  @@ fun value () -> return (OK (Int.to_string value))
;;

let%expect_test "Context applicative composes dependency injection" =
  let response =
    compile_exn [ group [ dependency_route ] ] |> Compiled.app |> fun app ->
    call app `GET "/dependency"
  in
  Stdlib.Printf.printf
    "%d %s"
    (Typed_endpoint_testing.Response.status response)
    (Typed_endpoint_testing.Response.body response);
  [%expect {| 200 42 |}]
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

let group_context =
  let guard =
    Guard.v
      ~security:[ Security.require bearer ]
      ~status:`Unauthorized
      ~response:(Response.json (module Error_payload))
      ~check:(fun request ->
        match B.header request "authorization" with
        | Some "Bearer group-token" -> return (Ok ())
        | _ ->
          return
            (Error Error_payload.{ kind = "unauthorized"; message = "invalid token" }))
      ()
  in
  let open Context.Applicative_infix in
  guard *> Dependency.value "shared"
;;

let grouped_route segment =
  make_in_group
    ~meth:B.get
    ~path:(s segment /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"Injected group dependency" ()))
  @@ fun dependency () -> return (OK (dependency ^ ":" ^ segment))
;;

let%expect_test "a group context is typed, shared, and documented per route" =
  let compiled =
    compile_exn
      [ Group.make_with_context
          ~context:group_context
          ~description:"Contextual routes"
          [ grouped_route "group-a"; grouped_route "group-b" ]
      ]
  in
  let app = Compiled.app compiled in
  let rejected = call app `GET "/group-a" in
  let accepted =
    call app ~headers:[ "authorization", "Bearer group-token" ] `GET "/group-b"
  in
  let open Yojson.Safe.Util in
  let document = Compiled.openapi compiled in
  let operation segment =
    document |> member "paths" |> member ("/" ^ segment) |> member "get"
  in
  Stdlib.Printf.printf
    "%d %s\n%d %s\n"
    (Typed_endpoint_testing.Response.status rejected)
    (Typed_endpoint_testing.Response.body rejected)
    (Typed_endpoint_testing.Response.status accepted)
    (Typed_endpoint_testing.Response.body accepted);
  List.iter [ "group-a"; "group-b" ] ~f:(fun segment ->
    let operation = operation segment in
    Stdlib.Printf.printf
      "%s:security=%d,unauthorized=%b "
      segment
      (operation |> member "security" |> to_list |> List.length)
      (not (Yojson.Safe.equal (operation |> member "responses" |> member "401") `Null)));
  [%expect
    {|
    401 {"kind":"unauthorized","message":"invalid token"}
    200 shared:group-b
    group-a:security=1,unauthorized=true group-b:security=1,unauthorized=true |}]
;;

let secured_route =
  let guard =
    Guard.v
      ~security:[ Security.require bearer; Security.require api_key ]
      ~status:`Unauthorized
      ~response:(Response.json (module Error_payload))
      ~check:(fun _request -> return (Ok ()))
      ()
  in
  make_with
    ~context:guard
    ~meth:B.get
    ~path:(s "secure" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"OK" ()))
  @@ fun () () -> return (OK "ok")
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
  @@ fun () -> return (OK "conflict")
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

let%expect_test "routes with indistinguishable capture shapes are rejected" =
  let string = Parameter.string ~description:"Identifier" () in
  let route name =
    make
      ~meth:B.get
      ~path:(s "pets" / param name string /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"Pet" ()))
    @@ fun _id () -> return (OK "pet")
  in
  print_compile_errors [ group [ route "id"; route "name" ] ];
  [%expect {| ambiguous route: get /pets/:name conflicts with /pets/:id |}]
;;

let%expect_test "group prefixes must contain canonical static segments" =
  print_compile_errors
    [ Group.make ~prefix:[ "/v1" ] ~description:"Invalid prefix" [ primitive_route ] ];
  [%expect {| invalid group prefix segment: /v1 |}]
;;

let%expect_test "typed routes reject wildcards and undeclared captures" =
  let route segment =
    make
      ~meth:B.get
      ~path:(s segment /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"Response" ()))
    @@ fun () -> return (OK "response")
  in
  print_compile_errors [ group [ route "*"; route ":undeclared" ] ];
  [%expect
    {|
    invalid typed route path: get /*
    path captures do not match declared parameters: get /:undeclared; declared [], captures [undeclared] |}]
;;

let%expect_test "a root route is joined to its group prefix without a trailing slash" =
  let route =
    make
      ~meth:B.get
      ~path:nil
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"Root" ()))
    @@ fun () -> return (OK "root")
  in
  let compiled =
    compile_exn [ Group.make ~prefix:[ "v1" ] ~description:"Version root" [ route ] ]
  in
  let response = call (Compiled.app compiled) `GET "/v1" in
  let open Yojson.Safe.Util in
  let documented =
    Compiled.openapi compiled |> member "paths" |> member "/v1" |> member "get"
  in
  Stdlib.Printf.printf
    "runtime=%s documented=%b"
    (Typed_endpoint_testing.Response.body response)
    (not (Yojson.Safe.equal documented `Null));
  [%expect {| runtime=root documented=true |}]
;;

let%expect_test "duplicate parameters in one location are rejected" =
  let string = Parameter.string ~description:"Tag" () in
  let route =
    make
      ~meth:B.get
      ~path:(s "search" / query "tag" string / query "tag" string /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"Search result" ()))
    @@ fun _first _second () -> return (OK "result")
  in
  print_compile_errors [ group [ route ] ];
  [%expect {| duplicate query parameter tag: get /search |}]
;;

let%expect_test "response status must be a valid HTTP status" =
  let route =
    make
      ~meth:B.get
      ~path:(s "invalid-status" /? nil)
      ~request:Request.empty
      ~responses:(code [ `Code 99 ] (Response.text ~description:"Invalid" ()))
    @@ fun () -> return (Code (`Code 99, "invalid"))
  in
  print_compile_errors [ group [ route ] ];
  [%expect {| invalid response status 99: get /invalid-status |}]
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
      ~check:(fun _request -> return (Ok ()))
      ()
  in
  let route =
    make_with
      ~context:guard
      ~meth:B.get
      ~path:(s "scope" /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"OK" ()))
    @@ fun () () -> return (OK "ok")
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
      ~check:(fun _request -> return (Ok ()))
      ()
  in
  let route =
    make_with
      ~context:(Context.both (guard first) (guard second))
      ~meth:B.get
      ~path:(s "scheme-conflict" /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"OK" ()))
    @@ fun ((), ()) () -> return (OK "ok")
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
