open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
module Io = Endpoint.Io
open Io.Let_syntax
open Endpoint
open Dsl
open Staged

module Testing_conformance = Typed_endpoint_testing.Backend_conformance.Make (struct
    module Backend = Typed_endpoint_testing

    let call app ?headers ?body meth target =
      Typed_endpoint_testing.Client.call app ?headers ?body meth target
    ;;

    let status = Typed_endpoint_testing.Response.status
    let header = Typed_endpoint_testing.Response.header
    let body response = Typed_endpoint_testing.Response.body response
  end)

module Item = struct
  type t =
    { id : int
    ; name : string
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:(Json_schema.of_ppx t_jsonschema)
      ~schema_name:"Item"
      ~description:"An item"
      ()
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
      ~schema:(Json_schema.of_ppx t_jsonschema)
      ~schema_name:"RequestError"
      ~description:"A request error"
      ()
  ;;
end

let error_kind : Decode_error.t -> string = function
  | Invalid_parameter _ -> "invalid_parameter"
  | Missing_parameter _ -> "missing_parameter"
  | Duplicate_parameter _ -> "duplicate_parameter"
  | Invalid_json _ -> "invalid_json"
  | Invalid_body _ -> "invalid_body"
  | Unsupported_media_type _ -> "unsupported_media_type"
  | Body_too_large _ -> "body_too_large"
;;

let error_message : Decode_error.t -> string = function
  | Invalid_parameter { error; _ } | Invalid_json { error } | Invalid_body { error } ->
    error
  | Missing_parameter { name; _ } -> "missing " ^ name
  | Duplicate_parameter { name; _ } -> "duplicate " ^ name
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
  let ok = Response.case `OK (Response.json (module Item)) in
  post / "items"
  |> documented ~operation_id:"echoItem"
  |> accepts (Request.json ~max_body_bytes (module Item))
  |> returns ok
  |> handle @@ fun item -> respond ok item
;;

let binary_route =
  let ok = Response.case `OK (Response.text ~description:"Byte length" ()) in
  post / "binary"
  |> documented ~operation_id:"uploadBinary"
  |> accepts (Request.binary ~max_body_bytes:4 ~description:"Opaque bytes" ())
  |> returns ok
  |> handle @@ fun bytes -> respond ok (Int.to_string (String.length bytes))
;;

let call = Typed_endpoint_testing.Client.call

let%test_unit "testing backend passes the shared conformance suite" =
  Testing_conformance.run ()
;;

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
  let ok = Response.case `OK (Response.text ~description:"Decoded values" ()) in
  get
  / "primitive"
  /: arg "id" (Parameter.int ~description:"Integer identifier" ())
  /! arg "enabled" (Parameter.bool ~description:"Whether it is enabled" ())
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun id enabled () ->
     respond ok (Int.to_string id ^ ":" ^ Bool.to_string enabled)
;;

let staged_route =
  let ok = Response.case `OK (Response.text ~description:"Decoded values" ()) in
  get
  / "staged"
  /: arg "id" (Parameter.int ~description:"Identifier" ())
  /! arg "enabled" (Parameter.bool ~description:"Enabled" ())
  |> documented
       ~operation_id:"stagedRoute"
       ~summary:"Staged route"
       ~description:"Exercises the URI-first staged facade."
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun id enabled () ->
     respond ok (Int.to_string id ^ ":" ^ Bool.to_string enabled)
;;

let%expect_test "staged URI DSL preserves handler order and OpenAPI" =
  let compiled = compile_exn [ group [ staged_route ] ] in
  let response = call (Compiled.app compiled) `GET "/staged/42?enabled=true" in
  let open Yojson.Safe.Util in
  let operation =
    Compiled.openapi compiled |> member "paths" |> member "/staged/{id}" |> member "get"
  in
  Stdlib.Printf.printf
    "%d %s operation=%s params=%d"
    (Typed_endpoint_testing.Response.status response)
    (Typed_endpoint_testing.Response.body response)
    (operation |> member "operationId" |> to_string)
    (operation |> member "parameters" |> to_list |> List.length);
  [%expect {| 200 42:true operation=stagedRoute params=2 |}]
;;

let%expect_test "typed request and response headers drive runtime and OpenAPI" =
  let version =
    Header.required "X-Api-Version" (Header.int ~description:"API version" ())
  in
  let request_id =
    Header.optional "X-Request-Id" (Header.string ~description:"Request identifier" ())
  in
  let result =
    Header.required "X-Result" (Header.string ~description:"Result marker" ())
  in
  let route =
    let ok =
      Response.case
        `OK
        (Response.text ~description:"Header result" () |> Response.with_header result)
    in
    get / "headers"
    |> header version
    |> header request_id
    |> documented ~operation_id:"typedHeaders"
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun version request_id () ->
       let request_id = Option.value request_id ~default:"none" in
       respond ok ("ok", Int.to_string version ^ ":" ^ request_id)
  in
  let compiled = compile_exn [ group [ route ] ] in
  let response =
    call
      (Compiled.app compiled)
      ~headers:[ "x-api-version", "2"; "X-Request-ID", "req-1" ]
      `GET
      "/headers"
  in
  let missing = call (Compiled.app compiled) `GET "/headers" in
  let open Yojson.Safe.Util in
  let operation =
    Compiled.openapi compiled |> member "paths" |> member "/headers" |> member "get"
  in
  let parameters = operation |> member "parameters" |> to_list in
  let documented_header =
    operation
    |> member "responses"
    |> member "200"
    |> member "headers"
    |> member "X-Result"
  in
  Stdlib.Printf.printf
    "status=%d body=%s result=%s missing=%d params=%d required=%b"
    (Typed_endpoint_testing.Response.status response)
    (Typed_endpoint_testing.Response.body response)
    (Typed_endpoint_testing.Response.header response "x-result"
     |> Option.value ~default:"none")
    (Typed_endpoint_testing.Response.status missing)
    (List.length parameters)
    (documented_header |> member "required" |> to_bool);
  [%expect {| status=200 body=2:req-1 result=ok missing=400 params=2 required=true |}]
;;

let%expect_test "response header values reject line breaks without echoing the value" =
  let unsafe =
    Header.required "X-Value" (Header.string ~description:"Validated value" ())
  in
  let route =
    let ok =
      Response.case
        `OK
        (Response.text ~description:"Response" () |> Response.with_header unsafe)
    in
    get / "unsafe-header"
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun () -> respond ok ("bad\r\nInjected: yes", "body")
  in
  let app = compile_exn [ group [ route ] ] |> Compiled.app in
  (try ignore (call app `GET "/unsafe-header" : Typed_endpoint_testing.response) with
   | Runtime_error error -> Stdlib.print_endline (Runtime_error.to_string error));
  [%expect
    {| invalid response header X-Value: value contains a carriage return or line feed |}]
;;

let empty_response_route =
  let ok = Response.case `OK (Response.empty ~description:"No representation" ()) in
  get / "empty"
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun () -> respond ok ()
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
    let ok = Response.case `OK (Response.text ~description:"Captured" ()) in
    get / "priority" /: arg "value" (Parameter.string ~description:"Captured value" ())
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun value () -> respond ok ("capture:" ^ value)
  in
  let fixed =
    let ok = Response.case `OK (Response.text ~description:"Static" ()) in
    get / "priority" / "fixed"
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun () -> respond ok "static"
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

let dependency_context =
  let open Context.Let_syntax in
  let%map values = Context.all [ Dependency.value 20; Dependency.value 21 ]
  and final_value = Context.return 1 in
  List.fold values ~init:final_value ~f:( + )
;;

let dependency_route =
  let ok = Response.case `OK (Response.text ~description:"Injected value" ()) in
  get / "dependency"
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle_with ~context:dependency_context @@ fun value () ->
     respond ok (Int.to_string value)
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
  let ok =
    Response.case `OK (Response.text ~description:"Injected group dependency" ())
  in
  get / segment |> documented |> accepts Request.empty |> returns ok
  ==> fun dependency () -> respond ok (dependency ^ ":" ^ segment)
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

let observed_route =
  let ok = Response.case `OK (Response.text ~description:"Observed" ()) in
  get / "observed" /: arg "id" (Parameter.int ~description:"Identifier" ())
  |> documented ~operation_id:"observedRoute" ~tags:[ "endpoint" ]
  |> accepts Request.empty
  |> returns ok
  ==> fun id dependency () -> respond ok (dependency ^ ":" ^ Int.to_string id)
;;

let%expect_test "route-aware interceptors receive stable templates and metadata" =
  let seen = ref [] in
  let interceptor ~(route_info : Route_info.t) ~request:_ ~next =
    seen
    := !seen
       @ [ String.concat
             ~sep:"|"
             [ route_info.method_
             ; route_info.path_template
             ; Option.value route_info.operation_id ~default:"none"
             ; String.concat route_info.tags ~sep:","
             ; Int.to_string (List.length route_info.security)
             ]
         ];
    next ()
  in
  let compiled =
    compile_exn
      ~interceptors:[ interceptor ]
      [ Group.make_with_context
          ~prefix:[ "v1" ]
          ~tags:[ "group" ]
          ~context:group_context
          ~description:"Observed routes"
          [ observed_route ]
      ]
  in
  let response =
    call
      (Compiled.app compiled)
      ~headers:[ "authorization", "Bearer group-token" ]
      `GET
      "/v1/observed/7"
  in
  Stdlib.Printf.printf
    "%d %s %s"
    (Typed_endpoint_testing.Response.status response)
    (Typed_endpoint_testing.Response.body response)
    (List.hd_exn !seen);
  [%expect {| 200 shared:7 GET|/v1/observed/{id}|observedRoute|endpoint,group|1 |}]
;;

let%expect_test "principal retains typed identity and deterministic scopes" =
  let principal = Principal.v ~identity:"alice" ~scopes:[ "write"; "read"; "read" ] () in
  Stdlib.Printf.printf
    "%s scopes=%s write=%b"
    (Principal.identity principal)
    (String.concat (Principal.scopes principal) ~sep:",")
    (Principal.has_scope principal "write");
  [%expect {| alice scopes=read,write write=true |}]
;;

let secured_guard =
  Guard.v
    ~security:[ Security.require bearer; Security.require api_key ]
    ~status:`Unauthorized
    ~response:(Response.json (module Error_payload))
    ~check:(fun _request -> return (Ok ()))
    ()
;;

let secured_route =
  let ok = Response.case `OK (Response.text ~description:"OK" ()) in
  get / "secure"
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle_with ~context:secured_guard @@ fun () () -> respond ok "ok"
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
    Metadata.v
      ~schema:(Json_schema.of_ppx t_jsonschema)
      ~schema_name:"Item"
      ~description:"Wrong item"
      ()
  ;;
end

let conflict_route =
  let ok = Response.case `OK (Response.json (module Conflicting_item)) in
  get / "conflict"
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun () -> respond ok "conflict"
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
    let ok = Response.case `OK (Response.text ~description:"Pet" ()) in
    get / "pets" /: arg name string
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun _id () -> respond ok "pet"
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
    let ok = Response.case `OK (Response.text ~description:"Response" ()) in
    get / segment
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun () -> respond ok "response"
  in
  print_compile_errors [ group [ route "*"; route ":undeclared" ] ];
  [%expect
    {|
    invalid typed route path: get /*
    path captures do not match declared parameters: get /:undeclared; declared [], captures [undeclared] |}]
;;

let%expect_test "a root route is joined to its group prefix without a trailing slash" =
  let route =
    let ok = Response.case `OK (Response.text ~description:"Root" ()) in
    get
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun () -> respond ok "root"
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
    let ok = Response.case `OK (Response.text ~description:"Search result" ()) in
    get / "search" /? arg "tag" string /? arg "tag" string
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun _first _second () -> respond ok "result"
  in
  print_compile_errors [ group [ route ] ];
  [%expect {| duplicate query parameter tag: get /search |}]
;;

let%expect_test "header declarations validate names and duplicates" =
  let codec = Header.string ~description:"Header" () in
  let invalid = Header.required "Bad Header" codec in
  let duplicate = Header.required "X-Value" codec in
  let invalid_route =
    let ok = Response.case `OK (Response.text ~description:"Response" ()) in
    get / "invalid-header"
    |> header invalid
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun _value () -> respond ok "ok"
  in
  let duplicate_route =
    let ok =
      Response.case
        `OK
        (Response.text ~description:"Response" ()
         |> Response.with_header duplicate
         |> Response.with_header duplicate)
    in
    get / "duplicate-header"
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle @@ fun () -> respond ok ("first", ("second", "ok"))
  in
  print_compile_errors [ group [ invalid_route; duplicate_route ] ];
  [%expect
    {|
    invalid header name Bad Header: get /invalid-header
    duplicate response header X-Value for status 200: get /duplicate-header |}]
;;

let%expect_test "response status must be a valid HTTP status" =
  let route =
    let invalid = Response.case (`Code 99) (Response.text ~description:"Invalid" ()) in
    get / "invalid-status"
    |> documented
    |> accepts Request.empty
    |> returns invalid
    |> handle @@ fun () -> respond invalid "invalid"
  in
  print_compile_errors [ group [ route ] ];
  [%expect {| invalid response status 99: get /invalid-status |}]
;;

let%expect_test "duplicate response case statuses are rejected" =
  let first = Response.case `OK (Response.text ~description:"First" ()) in
  let second = Response.case `OK (Response.text ~description:"Second" ()) in
  let route =
    get / "duplicate-response"
    |> documented
    |> accepts Request.empty
    |> returns (first <|> second)
    |> handle @@ fun () -> respond first "first"
  in
  print_compile_errors [ group [ route ] ];
  [%expect {| duplicate response status 200: get /duplicate-response |}]
;;

let%expect_test "a handler must return a case from its endpoint" =
  let declared = Response.case `OK (Response.text ~description:"Declared" ()) in
  let other = Response.case `OK (Response.text ~description:"Other" ()) in
  let route =
    get / "undeclared-case"
    |> documented
    |> accepts Request.empty
    |> returns declared
    |> handle @@ fun () -> respond other "other"
  in
  let app = compile_exn [ group [ route ] ] |> Compiled.app in
  (try ignore (call app `GET "/undeclared-case" : Typed_endpoint_testing.response) with
   | Runtime_error error -> Stdlib.print_endline (Runtime_error.to_string error));
  [%expect
    {|
    handler returned undeclared response case for status 200 for get /undeclared-case; declared: [200] |}]
;;

let%expect_test "each response case retains its own payload codec" =
  let ok = Response.case `OK (Response.json (module Item)) in
  let not_found = Response.case `Not_found (Response.json (module Error_payload)) in
  let route =
    get / "case-choice" /? arg "missing" (Parameter.bool ~description:"Missing" ())
    |> documented
    |> accepts Request.empty
    |> returns (ok <|> not_found)
    |> handle @@ fun missing () ->
       match missing with
       | Some true ->
         respond not_found Error_payload.{ kind = "missing"; message = "gone" }
       | Some false | None -> respond ok Item.{ id = 7; name = "present" }
  in
  let app = compile_exn [ group [ route ] ] |> Compiled.app in
  let response = call app `GET "/case-choice" in
  Stdlib.Printf.printf
    "%d %s"
    (Typed_endpoint_testing.Response.status response)
    (Typed_endpoint_testing.Response.body response);
  [%expect {| 200 {"id":7,"name":"present"} |}];
  let response = call app `GET "/case-choice?missing=true" in
  Stdlib.Printf.printf
    "%d %s"
    (Typed_endpoint_testing.Response.status response)
    (Typed_endpoint_testing.Response.body response);
  [%expect {| 404 {"kind":"missing","message":"gone"} |}]
;;

let%expect_test "typed response cases cover arbitrary statuses" =
  let route =
    let accepted = Response.case `Accepted (Response.json (module Item)) in
    let conflict = Response.case `Conflict (Response.json (module Error_payload)) in
    let unavailable =
      Response.case `Service_unavailable (Response.json (module Error_payload))
    in
    let redirect = Response.case `Temporary_redirect (Response.json (module Item)) in
    get / "status-families"
    |> documented
    |> accepts Request.empty
    |> returns (accepted <|> conflict <|> unavailable <|> redirect)
    |> handle @@ fun () -> respond accepted Item.{ id = 202; name = "accepted" }
  in
  let compiled = compile_exn [ group [ route ] ] in
  let response = call (Compiled.app compiled) `GET "/status-families" in
  Stdlib.Printf.printf
    "%d %s\n"
    (Typed_endpoint_testing.Response.status response)
    (Typed_endpoint_testing.Response.body response);
  [%expect {| 202 {"id":202,"name":"accepted"} |}];
  let response_codes =
    let open Yojson.Safe.Util in
    Compiled.openapi compiled
    |> member "paths"
    |> member "/status-families"
    |> member "get"
    |> member "responses"
    |> to_assoc
    |> List.map ~f:fst
    |> List.sort ~compare:String.compare
  in
  Stdlib.print_endline (String.concat ~sep:"," response_codes);
  [%expect {| 202,307,409,503 |}]
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
    let ok = Response.case `OK (Response.text ~description:"OK" ()) in
    get / "scope"
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle_with ~context:guard @@ fun () () -> respond ok "ok"
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
    let ok = Response.case `OK (Response.text ~description:"OK" ()) in
    get / "scheme-conflict"
    |> documented
    |> accepts Request.empty
    |> returns ok
    |> handle_with ~context:(Context.both (guard first) (guard second))
       @@ fun ((), ()) () -> respond ok "ok"
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
