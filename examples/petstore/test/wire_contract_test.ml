open! Base
module Backend = Typed_endpoint_testing
module Database = Petstore_app.Database_memory.Make (Backend.Io)

module Session_runtime = struct
  let clock = ref 0.
  let counter = ref 0
  let now () = !clock

  let token () =
    Int.incr counter;
    Ok ("session-" ^ Int.to_string !counter)
  ;;
end

module App =
  Petstore_app.Routes.Make (Backend) (Database) (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)
    (Database.Session_repository)
    (Session_runtime)

module Endpoint = App.Endpoint

let auth = Petstore_app.Routes.{ bearer_token = "wire-token"; api_key = "wire-key" }
let app = App.compile ~auth ~database:(Database.create ()) () |> Endpoint.Compiled.app

let send ?(headers = []) ?(body = "") meth target =
  Typed_endpoint_testing.Request.v ~headers ~body ~meth ~target ()
  |> Typed_endpoint_testing.dispatch app
;;

let status = Typed_endpoint_testing.Response.status
let header = Typed_endpoint_testing.Response.header
let body = Typed_endpoint_testing.Response.body

let check condition message =
  if not condition then
    failwith ("wire contract: " ^ message)
;;

let check_json_response response expected_status =
  check (Int.equal (status response) expected_status) "unexpected JSON status";
  check
    (Option.equal String.equal (header response "Content-Type") (Some "application/json"))
    "unexpected JSON Content-Type"
;;

let field name = function
  | `Assoc fields -> List.Assoc.find fields name ~equal:String.equal
  | _ -> None
;;

let () =
  let unauthorized = send `GET "/pet/findByStatus?status=available" in
  check_json_response unauthorized 401;
  check
    (String.equal
       (body unauthorized)
       {|{"code":401,"type":"unauthorized","message":"invalid credentials"}|})
    "unauthorized JSON shape";
  let create_body =
    {|{"id":10,"username":"alice","firstName":"Alice","password":"secret"}|}
  in
  let created =
    send ~headers:[ "content-type", "application/json" ] ~body:create_body `POST "/user"
  in
  check_json_response created 200;
  let created_json = Yojson.Safe.from_string (body created) in
  check
    (Option.equal
       Yojson.Safe.equal
       (field "firstName" created_json)
       (Some (`String "Alice")))
    "camelCase response field";
  check (Option.is_none (field "first_name" created_json)) "snake_case field leaked";
  check (Option.is_none (field "password" created_json)) "password leaked from create";
  let found = send `GET "/user/alice" in
  check
    (Option.is_none (field "password" (Yojson.Safe.from_string (body found))))
    "password leaked from GET";
  let login =
    send
      ~headers:[ "content-type", "application/json" ]
      ~body:{|{"username":"alice","password":"secret"}|}
      `POST
      "/user/login"
  in
  check_json_response login 200;
  check (String.equal (body login) {|"session-1"|}) "login token encoding";
  check (Option.is_none (header login "x-rate-limit")) "fictional rate-limit header";
  check (Option.is_none (header login "x-expires-after")) "fictional expiration header";
  let missing_password =
    send
      ~headers:[ "content-type", "application/json" ]
      ~body:{|{"username":"alice"}|}
      `POST
      "/user/login"
  in
  check_json_response missing_password 400;
  let get_login = send `GET "/user/login?username=alice&password=secret" in
  check (Int.equal (status get_login) 404) "GET login still authenticates";
  let authorized =
    send
      ~headers:[ "authorization", "bEaReR session-1" ]
      `GET
      "/pet/findByStatus?status=available"
  in
  check_json_response authorized 200;
  let logout =
    send ~headers:[ "authorization", "Bearer session-1" ] `POST "/user/logout"
  in
  check (Int.equal (status logout) 200 && String.is_empty (body logout)) "session logout";
  check (Option.is_none (header logout "Content-Type")) "logout Content-Type";
  check_json_response
    (send
       ~headers:[ "authorization", "Bearer session-1" ]
       `GET
       "/pet/findByStatus?status=available")
    401;
  check
    (Int.equal
       (status
          (send ~headers:[ "authorization", "Bearer wire-token" ] `POST "/user/logout"))
       200)
    "demo logout";
  check_json_response
    (send
       ~headers:[ "authorization", "bearer wire-token" ]
       `GET
       "/pet/findByStatus?status=available")
    200;
  let bulk =
    send
      ~headers:[ "content-type", "application/json" ]
      ~body:{|[{"username":"bob","password":"one"}]|}
      `POST
      "/user/createWithArray"
  in
  check_json_response bulk 200;
  check
    (Option.is_none (field "password" (Yojson.Safe.from_string (body bulk))))
    "password leaked from batch";
  let invalid_path = send `GET "/user/%20" in
  check_json_response invalid_path 400;
  let invalid_json = Yojson.Safe.from_string (body invalid_path) in
  check
    (Option.equal Yojson.Safe.equal (field "code" invalid_json) (Some (`Int 400)))
    "decode error code";
  check
    (Option.equal
       Yojson.Safe.equal
       (field "type" invalid_json)
       (Some (`String "decode_error")))
    "decode error type";
  let deleted = send `DELETE "/user/alice" in
  check (Int.equal (status deleted) 200) "delete status";
  check (String.is_empty (body deleted)) "empty response body";
  check (Option.is_none (header deleted "content-type")) "empty response Content-Type";
  let missing = send `GET "/definitely-missing" in
  check (Int.equal (status missing) 404) "router 404 status";
  check
    (Option.equal
       String.equal
       (header missing "content-type")
       (Some "text/plain; charset=utf-8"))
    "router 404 Content-Type"
;;
