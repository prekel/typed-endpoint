open! Base
module Backend = Typed_endpoint_testing
module Database = Petstore_app.Database_memory.Make (Backend.Io)

module App =
  Petstore_app.Routes.Make (Backend) (Database) (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)

module Dsl = App.Endpoint.Dsl

let auth = Petstore_app.Routes.{ bearer_token = "wire-token"; api_key = "wire-key" }
let app = App.compile ~auth ~database:(Database.create ()) () |> Dsl.Compiled.app

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
  let login = send `GET "/user/login?username=alice&password=secret" in
  check_json_response login 200;
  check (String.equal (body login) {|"alice-session-token"|}) "login token encoding";
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
