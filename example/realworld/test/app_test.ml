open! Base
module App = Realworld_app.Routes.Make (Memory_backend) (Memory_backend.Request)
module D = App.Endpoint.D

let service = Realworld_app.Article_service.seeded ()
let compiled = App.compile service
let app = D.Compiled.app compiled
let authorization = Cohttp.Header.init_with "authorization" "Bearer demo-token"

let dispatch ?headers ?(meth = `GET) ?(body = "") target =
  Memory_backend.dispatch app ?headers ~meth ~target ~body ()
;;

let expect_status expected response =
  assert (Int.equal expected (Memory_backend.Response.status response))
;;

let json (response : Memory_backend.Response.t) =
  Yojson.Safe.from_string (Memory_backend.Response.body response)
;;

let member name value = Yojson.Safe.Util.member name value

let () =
  let first_page = dispatch "/api/articles?page=1" in
  expect_status 200 first_page;
  assert (Int.equal 2 (json first_page |> member "total" |> Yojson.Safe.Util.to_int));
  let rejected =
    dispatch
      ~meth:`POST
      ~body:{|{"title":"New article","body":"Created in a framework-free test."}|}
      "/api/articles"
  in
  expect_status 401 rejected;
  assert (
    String.equal
      "missing or invalid bearer token"
      (json rejected |> member "message" |> Yojson.Safe.Util.to_string));
  let invalid =
    dispatch
      ~headers:authorization
      ~meth:`POST
      ~body:{|{"title":"","body":"Body"}|}
      "/api/articles"
  in
  expect_status 400 invalid;
  let created =
    dispatch
      ~headers:authorization
      ~meth:`POST
      ~body:{|{"title":"New article","body":"Created in a framework-free test."}|}
      "/api/articles"
  in
  expect_status 201 created;
  let created_json = json created in
  let created_id = created_json |> member "id" |> Yojson.Safe.Util.to_int in
  assert (
    String.equal
      "demo-user"
      (created_json |> member "author" |> Yojson.Safe.Util.to_string));
  let fetched = dispatch ("/api/articles/" ^ Int.to_string created_id) in
  expect_status 200 fetched;
  assert (Int.equal created_id (json fetched |> member "id" |> Yojson.Safe.Util.to_int));
  let malformed_id = dispatch "/api/articles/not-an-int" in
  expect_status 400 malformed_id;
  assert (
    String.equal
      "id: expected a positive integer"
      (json malformed_id |> member "message" |> Yojson.Safe.Util.to_string));
  let deleted =
    dispatch
      ~headers:authorization
      ~meth:`DELETE
      ("/api/articles/" ^ Int.to_string created_id)
  in
  expect_status 204 deleted;
  dispatch ("/api/articles/" ^ Int.to_string created_id) |> expect_status 404;
  let wrong_method = dispatch ~meth:`PATCH "/api/articles" in
  expect_status 405 wrong_method;
  let openapi = D.Compiled.openapi ~title:"Realworld example" compiled in
  let create_responses =
    openapi
    |> member "paths"
    |> member "/api/articles"
    |> member "post"
    |> member "responses"
  in
  assert (not (Yojson.Safe.equal (member "201" create_responses) `Null));
  assert (not (Yojson.Safe.equal (member "400" create_responses) `Null));
  assert (not (Yojson.Safe.equal (member "401" create_responses) `Null))
;;
