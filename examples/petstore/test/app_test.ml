open! Base
module App = Petstore_app.Routes.Make (Typed_endpoint_testing)
module Dsl = App.Endpoint.Dsl

let auth = Petstore_app.Routes.{ bearer_token = "test-token"; api_key = "test-key" }
let service = Petstore_app.Pet_service.create ()
let compiled = App.compile ~auth service
let routes = Dsl.Compiled.app compiled

let request ?(headers = []) ?(body = "") meth target =
  Typed_endpoint_testing.Request.v ~headers ~body ~meth ~target ()
  |> Typed_endpoint_testing.dispatch routes
;;

let json_headers =
  [ "authorization", "Bearer test-token"; "content-type", "application/json" ]
;;

let () =
  let pet =
    {|{"name":"Milo","photoUrls":["https://example.test/milo.jpg"],"status":"available"}|}
  in
  let created = request ~headers:json_headers ~body:pet `POST "/pet" in
  assert (Int.equal (Typed_endpoint_testing.Response.status created) 200);
  let created_json =
    Typed_endpoint_testing.Response.json created |> Result.ok_or_failwith
  in
  let id = Yojson.Safe.Util.(created_json |> member "id" |> to_int) in
  let found =
    request ~headers:[ "api_key", "test-key" ] `GET ("/pet/" ^ Int.to_string id)
  in
  assert (Int.equal (Typed_endpoint_testing.Response.status found) 200);
  let listed =
    request ~headers:[ "api_key", "test-key" ] `GET "/pet/findByStatus?status=available"
  in
  assert (Int.equal (Typed_endpoint_testing.Response.status listed) 200);
  let listed_json =
    Typed_endpoint_testing.Response.json listed |> Result.ok_or_failwith
  in
  assert (Int.equal (List.length (Yojson.Safe.Util.to_list listed_json)) 1);
  let rejected = request `GET ("/pet/" ^ Int.to_string id) in
  assert (Int.equal (Typed_endpoint_testing.Response.status rejected) 401);
  let openapi = request `GET "/openapi.json" in
  assert (Int.equal (Typed_endpoint_testing.Response.status openapi) 200);
  let document = Typed_endpoint_testing.Response.json openapi |> Result.ok_or_failwith in
  let paths = Yojson.Safe.Util.(document |> member "paths") in
  assert (not (Yojson.Safe.equal Yojson.Safe.Util.(paths |> member "/pet/{petId}") `Null));
  assert (Yojson.Safe.equal Yojson.Safe.Util.(paths |> member "/health") `Null);
  let pet_properties =
    Yojson.Safe.Util.(
      document
      |> member "components"
      |> member "schemas"
      |> member "Pet"
      |> member "properties")
  in
  assert (
    not (Yojson.Safe.equal Yojson.Safe.Util.(pet_properties |> member "photoUrls") `Null));
  assert (Yojson.Safe.equal Yojson.Safe.Util.(pet_properties |> member "photo_urls") `Null);
  let statuses =
    Yojson.Safe.Util.(pet_properties |> member "status" |> member "enum" |> to_list)
  in
  assert (Int.equal (List.length statuses) 3);
  let docs = request `GET "/docs" in
  assert (Int.equal (Typed_endpoint_testing.Response.status docs) 200);
  let content_type =
    Typed_endpoint_testing.Response.headers docs |> fun headers ->
    List.Assoc.find headers ~equal:String.equal "content-type"
  in
  assert (Option.equal String.equal content_type (Some "text/html; charset=utf-8"));
  let html = Typed_endpoint_testing.Response.body docs in
  assert (String.is_substring html ~substring:"SwaggerUIBundle");
  assert (String.is_substring html ~substring:"/openapi.json")
;;
