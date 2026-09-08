open! Base
module Backend = Typed_endpoint_testing
module Pet_repository = Petstore_app.Pet_repository_memory.Make (Backend.Io)
module Order_repository = Petstore_app.Order_repository_memory.Make (Backend.Io)
module User_repository = Petstore_app.User_repository_memory.Make (Backend.Io)

module App =
  Petstore_app.Routes.Make (Backend) (Pet_repository) (Order_repository) (User_repository)

module Dsl = App.Endpoint.Dsl

module Failing_pet_repository = struct
  include Pet_repository

  let inventory _ : (_, Petstore_app.Persistence_error.t) Result.t = Error `Unavailable
end

module Failing_app =
  Petstore_app.Routes.Make (Backend) (Failing_pet_repository) (Order_repository)
    (User_repository)

let auth = Petstore_app.Routes.{ bearer_token = "test-token"; api_key = "test-key" }

let compiled =
  App.compile
    ~auth
    ~pet_repository:(Pet_repository.create ())
    ~order_repository:(Order_repository.create ())
    ~user_repository:(User_repository.create ())
;;

let routes = Dsl.Compiled.app compiled
let request = Typed_endpoint_testing.Client.call routes
let bearer_headers = [ "authorization", "Bearer test-token" ]
let api_key_headers = [ "api_key", "test-key" ]
let json headers = ("content-type", "application/json") :: headers

let assert_status expected response =
  assert (Int.equal (Typed_endpoint_testing.Response.status response) expected)
;;

let response_json response =
  Typed_endpoint_testing.Response.json response |> Result.ok_or_failwith
;;

let create_pet ~name ~status ~tags =
  let tags = List.map tags ~f:(fun tag -> `Assoc [ "name", `String tag ]) in
  let body =
    Yojson.Safe.to_string
      (`Assoc
          [ "name", `String name
          ; "photoUrls", `List []
          ; "tags", `List tags
          ; "status", `String status
          ])
  in
  let response = request ~headers:(json bearer_headers) ~body `POST "/pet" in
  assert_status 200 response;
  Yojson.Safe.Util.(response_json response |> member "id" |> to_int)
;;

let test_pet_api () =
  let rejected = request `GET "/pet/findByStatus?status=available" in
  assert_status 401 rejected;
  let milo = create_pet ~name:"Milo" ~status:"available" ~tags:[ "friendly" ] in
  let _otis = create_pet ~name:"Otis" ~status:"available" ~tags:[ "playful" ] in
  let _luna = create_pet ~name:"Luna" ~status:"sold" ~tags:[ "friendly"; "quiet" ] in
  let by_status =
    request ~headers:bearer_headers `GET "/pet/findByStatus?status=available"
  in
  assert_status 200 by_status;
  assert (Int.equal (List.length Yojson.Safe.Util.(response_json by_status |> to_list)) 2);
  let by_tags =
    request ~headers:bearer_headers `GET "/pet/findByTags?tags=friendly,missing"
  in
  assert_status 200 by_tags;
  assert (Int.equal (List.length Yojson.Safe.Util.(response_json by_tags |> to_list)) 2);
  let page =
    request ~headers:bearer_headers `GET "/pet/search?status=available&page=2&limit=1"
  in
  assert_status 200 page;
  let page = response_json page in
  assert (
    Int.equal Yojson.Safe.Util.(page |> member "pagination" |> member "total" |> to_int) 2);
  assert (Int.equal (List.length Yojson.Safe.Util.(page |> member "items" |> to_list)) 1);
  let found = request ~headers:api_key_headers `GET ("/pet/" ^ Int.to_string milo) in
  assert_status 200 found;
  let patched =
    request
      ~headers:bearer_headers
      `POST
      ("/pet/" ^ Int.to_string milo ^ "?name=Milo-updated&status=pending")
  in
  assert_status 200 patched;
  let patched = response_json patched in
  assert (
    String.equal Yojson.Safe.Util.(patched |> member "name" |> to_string) "Milo-updated");
  assert (
    String.equal Yojson.Safe.Util.(patched |> member "status" |> to_string) "pending");
  let replacement =
    Yojson.Safe.to_string
      (`Assoc
          [ "id", `Int milo
          ; "name", `String "Milo-replaced"
          ; "photoUrls", `List []
          ; "status", `String "available"
          ])
  in
  let replaced = request ~headers:(json bearer_headers) ~body:replacement `PUT "/pet" in
  assert_status 200 replaced;
  let wrong_media =
    request
      ~headers:(("content-type", "text/plain") :: bearer_headers)
      ~body:"image"
      `POST
      ("/pet/" ^ Int.to_string milo ^ "/uploadImage")
  in
  assert_status 415 wrong_media;
  let uploaded =
    request
      ~headers:(("content-type", "application/octet-stream") :: bearer_headers)
      ~body:"image-bytes"
      `POST
      ("/pet/" ^ Int.to_string milo ^ "/uploadImage?additionalMetadata=profile")
  in
  assert_status 200 uploaded;
  assert (
    String.is_substring
      Yojson.Safe.Util.(response_json uploaded |> member "message" |> to_string)
      ~substring:"11 bytes");
  let inventory = request ~headers:api_key_headers `GET "/store/inventory" in
  assert_status 200 inventory;
  let inventory = response_json inventory in
  assert (Int.equal Yojson.Safe.Util.(inventory |> member "available" |> to_int) 2);
  assert (Int.equal Yojson.Safe.Util.(inventory |> member "sold" |> to_int) 1);
  milo
;;

let test_store_api pet_id =
  let body =
    Yojson.Safe.to_string
      (`Assoc
          [ "petId", `Int pet_id
          ; "quantity", `Int 2
          ; "shipDate", `String "2026-09-03T10:00:00Z"
          ; "status", `String "placed"
          ; "complete", `Bool false
          ])
  in
  let placed = request ~headers:(json []) ~body `POST "/store/order" in
  assert_status 200 placed;
  let order_id = Yojson.Safe.Util.(response_json placed |> member "id" |> to_int) in
  let found = request `GET ("/store/order/" ^ Int.to_string order_id) in
  assert_status 200 found;
  assert (
    Int.equal Yojson.Safe.Util.(response_json found |> member "petId" |> to_int) pet_id);
  let deleted = request `DELETE ("/store/order/" ^ Int.to_string order_id) in
  assert_status 200 deleted;
  let missing = request `GET ("/store/order/" ^ Int.to_string order_id) in
  assert_status 404 missing
;;

let user_json ?id ?username ?first_name ?password () =
  let fields =
    [ Option.map id ~f:(fun id -> "id", `Int id)
    ; Option.map username ~f:(fun username -> "username", `String username)
    ; Option.map first_name ~f:(fun name -> "firstName", `String name)
    ; Option.map password ~f:(fun password -> "password", `String password)
    ]
    |> List.filter_opt
  in
  `Assoc fields
;;

let test_user_api () =
  let alice =
    user_json ~id:10 ~username:"alice" ~first_name:"Alice" ~password:"secret" ()
  in
  let created =
    request ~headers:(json []) ~body:(Yojson.Safe.to_string alice) `POST "/user"
  in
  assert_status 200 created;
  let found = request `GET "/user/alice" in
  assert_status 200 found;
  let logged_in = request `GET "/user/login?username=alice&password=secret" in
  assert_status 200 logged_in;
  assert (Yojson.Safe.equal (response_json logged_in) (`String "alice-session-token"));
  let update =
    user_json ~username:"ignored" ~first_name:"Alicia" ~password:"new-secret" ()
  in
  let updated =
    request ~headers:(json []) ~body:(Yojson.Safe.to_string update) `PUT "/user/alice"
  in
  assert_status 200 updated;
  let found = request `GET "/user/alice" in
  assert_status 200 found;
  assert (
    String.equal
      Yojson.Safe.Util.(response_json found |> member "firstName" |> to_string)
      "Alicia");
  let users =
    `List
      [ user_json ~username:"bob" ~password:"one" ()
      ; user_json ~username:"carol" ~password:"two" ()
      ]
  in
  let bulk =
    request
      ~headers:(json [])
      ~body:(Yojson.Safe.to_string users)
      `POST
      "/user/createWithList"
  in
  assert_status 200 bulk;
  assert (
    String.equal
      Yojson.Safe.Util.(response_json bulk |> member "username" |> to_string)
      "carol");
  assert_status 200 (request `GET "/user/logout");
  assert_status 200 (request `DELETE "/user/alice");
  assert_status 404 (request `GET "/user/alice")
;;

let test_openapi () =
  let response = request `GET "/openapi.json" in
  assert_status 200 response;
  let document = response_json response in
  let open Yojson.Safe.Util in
  assert (
    String.equal
      (document |> member "info" |> member "version" |> to_string)
      "1.0.29-SNAPSHOT");
  let paths = document |> member "paths" in
  let operations =
    [ "/pet", "put", "updatePet"
    ; "/pet", "post", "addPet"
    ; "/pet/findByStatus", "get", "findPetsByStatus"
    ; "/pet/findByTags", "get", "findPetsByTags"
    ; "/pet/{petId}", "get", "getPetById"
    ; "/pet/{petId}", "post", "updatePetWithForm"
    ; "/pet/{petId}", "delete", "deletePet"
    ; "/pet/{petId}/uploadImage", "post", "uploadFile"
    ; "/store/inventory", "get", "getInventory"
    ; "/store/order", "post", "placeOrder"
    ; "/store/order/{orderId}", "get", "getOrderById"
    ; "/store/order/{orderId}", "delete", "deleteOrder"
    ; "/user", "post", "createUser"
    ; "/user/createWithList", "post", "createUsersWithListInput"
    ; "/user/login", "get", "loginUser"
    ; "/user/logout", "get", "logoutUser"
    ; "/user/{username}", "get", "getUserByName"
    ; "/user/{username}", "put", "updateUser"
    ; "/user/{username}", "delete", "deleteUser"
    ]
  in
  List.iter operations ~f:(fun (path, meth, operation_id) ->
    assert (
      String.equal
        (paths |> member path |> member meth |> member "operationId" |> to_string)
        operation_id));
  assert (not (Yojson.Safe.equal (paths |> member "/pet/search") `Null));
  assert (Yojson.Safe.equal (paths |> member "/health") `Null);
  let status_schema =
    paths
    |> member "/pet/findByStatus"
    |> member "get"
    |> member "responses"
    |> member "200"
    |> member "content"
    |> member "application/json"
    |> member "schema"
  in
  assert (String.equal (status_schema |> member "type" |> to_string) "array");
  let inventory_values =
    paths
    |> member "/store/inventory"
    |> member "get"
    |> member "responses"
    |> member "200"
    |> member "content"
    |> member "application/json"
    |> member "schema"
    |> member "additionalProperties"
  in
  assert (String.equal (inventory_values |> member "format" |> to_string) "int32");
  let upload_content =
    paths
    |> member "/pet/{petId}/uploadImage"
    |> member "post"
    |> member "requestBody"
    |> member "content"
    |> member "application/octet-stream"
    |> member "schema"
  in
  assert (String.equal (upload_content |> member "format" |> to_string) "binary");
  let schemas = document |> member "components" |> member "schemas" in
  List.iter [ "Pet"; "Order"; "User"; "ApiResponse" ] ~f:(fun name ->
    assert (not (Yojson.Safe.equal (schemas |> member name) `Null)));
  let property schema name =
    schemas |> member schema |> member "properties" |> member name
  in
  assert (String.equal (property "Pet" "id" |> member "format" |> to_string) "int64");
  assert (
    String.equal (property "Order" "shipDate" |> member "format" |> to_string) "date-time");
  assert (not (Yojson.Safe.equal (property "User" "firstName") `Null));
  assert (Yojson.Safe.equal (property "User" "first_name") `Null);
  assert (
    String.equal (property "ApiResponse" "code" |> member "format" |> to_string) "int32");
  let security path meth =
    paths |> member path |> member meth |> member "security" |> to_list
  in
  assert (Int.equal (List.length (security "/pet/{petId}" "get")) 2);
  assert (Int.equal (List.length (security "/store/inventory" "get")) 1);
  assert (
    Yojson.Safe.equal
      (paths |> member "/user" |> member "post" |> member "security")
      `Null);
  let security_schemes = document |> member "components" |> member "securitySchemes" in
  assert (
    String.equal
      (security_schemes |> member "api_key" |> member "in" |> to_string)
      "header");
  assert (
    String.equal
      (security_schemes
       |> member "petstore_auth"
       |> member "flows"
       |> member "implicit"
       |> member "authorizationUrl"
       |> to_string)
      "https://petstore3.swagger.io/oauth/authorize");
  let docs = request `GET "/docs" in
  assert_status 200 docs;
  assert (
    String.is_substring
      (Typed_endpoint_testing.Response.body docs)
      ~substring:"Five renderers");
  List.iter
    [ "/docs/swagger", "SwaggerUIBundle"
    ; "/docs/scalar", "Scalar.createApiReference"
    ; "/docs/rapidoc", "<rapi-doc"
    ; "/docs/redoc", "<redoc"
    ; "/docs/elements", "<elements-api"
    ]
    ~f:(fun (path, marker) ->
      let response = request `GET path in
      assert_status 200 response;
      assert (
        String.is_substring
          (Typed_endpoint_testing.Response.body response)
          ~substring:marker))
;;

let test_static_repository_substitution () =
  let routes =
    Failing_app.compile
      ~auth
      ~pet_repository:(Failing_pet_repository.create ())
      ~order_repository:(Order_repository.create ())
      ~user_repository:(User_repository.create ())
    |> Failing_app.Endpoint.Dsl.Compiled.app
  in
  let response =
    Typed_endpoint_testing.Client.call
      routes
      ~headers:api_key_headers
      `GET
      "/store/inventory"
  in
  assert_status 503 response;
  let response = response_json response in
  assert (
    String.equal
      Yojson.Safe.Util.(response |> member "type" |> to_string)
      "service_unavailable")
;;

let () =
  let pet_id = test_pet_api () in
  test_store_api pet_id;
  test_user_api ();
  test_openapi ();
  test_static_repository_substitution ()
;;
