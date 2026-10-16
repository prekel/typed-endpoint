open! Base
module B = Typed_endpoint_testing
module Database = Petstore_app.Database_memory.Make (B.Io)

module Runtime = struct
  let counter = ref 0
  let now () = 0.

  let token () =
    Int.incr counter;
    Ok ("access-session-" ^ Int.to_string !counter)
  ;;
end

module App =
  Petstore_app.Routes.Make (B) (Database) (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)
    (Database.Session_repository)
    (Runtime)

let auth = Petstore_app.Auth.{ bearer_token = "admin-demo"; api_key = "admin-key" }
let api_key = [ "api_key", "admin-key" ]
let bearer token = [ "authorization", "Bearer " ^ token ]
let json headers = ("content-type", "application/json") :: headers
let member = Yojson.Safe.Util.member
let body response = B.Response.json response |> Result.ok_or_failwith

let status expected response =
  let actual = B.Response.status response in
  if not (Int.equal actual expected) then
    Stdlib.failwith
      (Stdlib.Printf.sprintf
         "expected HTTP %d, got %d: %s"
         expected
         actual
         (B.Response.body response))
;;

let resolve = Contract_test_support.resolve_response_exn

let validates document schema json =
  let basic json = Yojson.Basic.from_string (Yojson.Safe.to_string json) in
  let root = `Assoc (("allOf", `List [ schema ]) :: Yojson.Safe.Util.to_assoc document) in
  match Jsonschema.create_validator_from_json ~schema:(basic root) () with
  | Error error ->
    Stdlib.failwith (Stdlib.Format.asprintf "%a" Jsonschema.pp_compile_error error)
  | Ok validator -> assert (Result.is_ok (Jsonschema.validate validator (basic json)))
;;

let () =
  let compiled = App.compile ~auth ~database:(Database.create ()) () in
  let send = B.Client.call (App.Endpoint.Compiled.app compiled) in
  let create username =
    let response =
      send
        ~headers:(json [])
        ~body:
          (Yojson.Safe.to_string
             (`Assoc
                 [ "username", `String username
                 ; "password", `String "secret"
                 ; "firstName", `String "Initial"
                 ]))
        `POST
        "/user"
    in
    status 200 response
  in
  let login username password =
    send
      ~headers:(json [])
      ~body:
        (Yojson.Safe.to_string
           (`Assoc [ "username", `String username; "password", `String password ]))
      `POST
      "/user/login"
  in
  let token username password =
    let response = login username password in
    status 200 response;
    body response |> Yojson.Safe.Util.to_string
  in
  let pet token =
    send ~headers:(bearer token) `GET "/pet/findByStatus?status=available"
  in
  create "alice";
  create "bob";
  let alice = token "alice" "secret" in
  let alice_second = token "alice" "secret" in
  let bob = token "bob" "secret" in
  status 401 (send ~headers:(json []) ~body:{|{"password":"secret"}|} `PUT "/user/alice");
  status 401 (send `DELETE "/user/alice");
  status 401 (send ~headers:(json []) ~body:{|[]|} `POST "/user/createWithArray");
  status
    401
    (send
       ~headers:(json [ "api_key", "wrong" ])
       ~body:{|[]|}
       `POST
       "/user/createWithArray");
  status
    200
    (send
       ~headers:(json (api_key @ bearer alice))
       ~body:{|{"password":"secret"}|}
       `PUT
       "/user/bob");
  status
    200
    (send
       ~headers:(json (api_key @ bearer "invalid"))
       ~body:{|{"password":"secret"}|}
       `PUT
       "/user/bob");
  status
    403
    (send ~headers:(json (bearer alice)) ~body:{|{"password":"secret"}|} `PUT "/user/bob");
  status 403 (send ~headers:(bearer alice) `DELETE "/user/bob");
  status
    403
    (send
       ~headers:(json (bearer alice))
       ~body:{|[{"username":"blocked","password":"secret"}]|}
       `POST
       "/user/createWithList");
  status 404 (send `GET "/user/blocked");
  status 400 (send ~headers:(json (bearer alice)) ~body:{|{}|} `PUT "/user/alice");
  status
    400
    (send
       ~headers:(json (bearer alice))
       ~body:{|{"username":"alice","password":"secret"}|}
       `PUT
       "/user/alice");
  List.iter
    [ {|{}|}
    ; {|{"username":"empty"}|}
    ; {|{"password":"secret"}|}
    ; {|{"username":"","password":"secret"}|}
    ; {|{"username":"   ","password":"secret"}|}
    ; {|{"username":"empty","password":""}|}
    ; {|{"username":"empty","password":null}|}
    ]
    ~f:(fun input -> status 400 (send ~headers:(json []) ~body:input `POST "/user"));
  let batch_input =
    {|[{"username":"carol","password":"one"},{"username":"dave","password":"two"}]|}
  in
  let batch =
    send ~headers:(json api_key) ~body:batch_input `POST "/user/createWithArray"
  in
  status 200 batch;
  let users = body batch |> Yojson.Safe.Util.to_list in
  assert (
    List.equal
      String.equal
      (List.map users ~f:(fun user ->
         member "username" user |> Yojson.Safe.Util.to_string))
      [ "carol"; "dave" ]);
  List.iter users ~f:(fun user ->
    assert (Yojson.Safe.equal (member "password" user) `Null));
  status 400 (send ~headers:(json api_key) ~body:"[]" `POST "/user/createWithList");
  status
    409
    (send
       ~headers:(json api_key)
       ~body:
         {|[{"username":"rollback","password":"one"},{"username":"alice","password":"duplicate"}]|}
       `POST
       "/user/createWithList");
  status 404 (send `GET "/user/rollback");
  status
    200
    (send
       ~headers:(json (bearer "admin-demo"))
       ~body:{|[{"username":"demo-created","password":"secret"}]|}
       `POST
       "/user/createWithList");
  status
    200
    (send
       ~headers:(json (bearer alice))
       ~body:{|{"password":"secret"}|}
       `PUT
       "/user/alice");
  status 200 (pet alice);
  status 200 (pet alice_second);
  let profile = send `GET "/user/alice" in
  status 200 profile;
  assert (Yojson.Safe.equal (body profile |> member "firstName") `Null);
  status
    200
    (send
       ~headers:(json (bearer alice))
       ~body:{|{"password":"new-secret"}|}
       `PUT
       "/user/alice");
  status 401 (pet alice);
  status 401 (pet alice_second);
  status 200 (pet bob);
  status 400 (login "alice" "secret");
  let replacement = token "alice" "new-secret" in
  let replacement_second = token "alice" "new-secret" in
  status 200 (send ~headers:(bearer replacement) `DELETE "/user/alice");
  status 401 (pet replacement);
  status 401 (pet replacement_second);
  status 404 (send `GET "/user/alice");
  status
    200
    (send ~headers:(json api_key) ~body:{|{"password":"admin-reset"}|} `PUT "/user/bob");
  status 401 (pet bob);
  let bob_replacement = token "bob" "admin-reset" in
  status 200 (send ~headers:(bearer "admin-demo") `DELETE "/user/bob");
  status 401 (pet bob_replacement);
  status 200 (pet "admin-demo");
  let document = App.Endpoint.Compiled.openapi compiled in
  let operation path meth = document |> member "paths" |> member path |> member meth in
  let response path meth code =
    operation path meth |> member "responses" |> member code |> resolve document
  in
  let schema path meth code =
    response path meth code
    |> member "content"
    |> member "application/json"
    |> member "schema"
  in
  let schemas = document |> member "components" |> member "schemas" in
  let schemes = document |> member "components" |> member "securitySchemes" in
  assert (Yojson.Safe.equal (member "petstore_auth" schemes) `Null);
  assert (
    Yojson.Safe.equal
      (member "session_auth" schemes |> member "scheme")
      (`String "bearer"));
  List.iter [ "/pet/findByTags"; "/pet/findByStatus" ] ~f:(fun path ->
    assert (
      Yojson.Safe.equal
        (operation path "get" |> member "security")
        (`List [ `Assoc [ "session_auth", `List [] ] ])));
  assert (Yojson.Safe.equal (operation "/user" "post" |> member "security") `Null);
  assert (not (Yojson.Safe.equal (response "/user/{username}" "put" "403") `Null));
  assert (
    Yojson.Safe.equal
      (member "UserCreate" schemas
       |> member "properties"
       |> member "id"
       |> member "default")
      `Null);
  assert (
    List.Assoc.mem
      (member "UserCreate" schemas
       |> member "properties"
       |> member "id"
       |> Yojson.Safe.Util.to_assoc)
      "default"
      ~equal:String.equal);
  let required name =
    member name schemas
    |> member "required"
    |> Yojson.Safe.Util.to_list
    |> List.map ~f:Yojson.Safe.Util.to_string
    |> List.sort ~compare:String.compare
  in
  assert (List.equal String.equal (required "UserCreate") [ "password"; "username" ]);
  assert (List.equal String.equal (required "UserUpdate") [ "password" ]);
  assert (
    Yojson.Safe.equal
      (member "UserUpdate" schemas |> member "properties" |> member "username")
      `Null);
  assert (
    Yojson.Safe.equal
      (member "PetPage" schemas |> member "additionalProperties")
      (`Bool false));
  assert (
    Yojson.Safe.equal
      (member "PetPage" schemas
       |> member "properties"
       |> member "pagination"
       |> member "additionalProperties")
      (`Bool false));
  assert (
    Yojson.Safe.equal
      (schema "/pet/findByTags" "get" "200" |> member "items")
      (`Assoc [ "$ref", `String "#/components/schemas/Pet" ]));
  let input =
    operation "/user/createWithArray" "post"
    |> member "requestBody"
    |> member "content"
    |> member "application/json"
    |> member "schema"
  in
  assert (
    Yojson.Safe.equal
      (member "items" input)
      (`Assoc [ "$ref", `String "#/components/schemas/UserCreate" ]));
  assert (Yojson.Safe.equal (member "minItems" input) (`Int 1));
  let output = schema "/user/createWithArray" "post" "200" in
  assert (
    Yojson.Safe.equal
      (member "items" output)
      (`Assoc [ "$ref", `String "#/components/schemas/User" ]));
  validates document output (body batch);
  validates document input (Yojson.Safe.from_string batch_input);
  validates
    document
    (schema "/user" "post" "400")
    (body (send ~headers:(json []) ~body:"{}" `POST "/user"));
  assert (
    Yojson.Safe.equal
      (response "/pet/{petId}/uploadImage" "post" "200" |> member "description")
      (`String "Image uploaded"));
  document
  |> member "paths"
  |> Yojson.Safe.Util.to_assoc
  |> List.iter ~f:(fun (path, item) ->
    Yojson.Safe.Util.to_assoc item
    |> List.iter ~f:(fun (meth, operation) ->
      if not (String.equal meth "parameters") then
        operation
        |> member "responses"
        |> Yojson.Safe.Util.to_assoc
        |> List.iter ~f:(fun (code, response) ->
          assert (Yojson.Safe.equal (member "$ref" response) `Null);
          let status = Int.of_string code in
          if status >= 400 then (
            let expected =
              match status with
              | 400 ->
                if String.equal path "/user/login" then
                  "Invalid request or credentials"
                else
                  "Invalid request"
              | 401 -> "Authentication required"
              | 403 -> "Insufficient permissions"
              | 404 ->
                if String.is_prefix path ~prefix:"/pet" then
                  "Pet not found"
                else if String.is_prefix path ~prefix:"/store/" then
                  "Order not found"
                else
                  "User not found"
              | 409 ->
                if String.equal path "/pet" then
                  "Pet already exists"
                else
                  "Username already exists"
              | 413 -> "Request body too large"
              | 415 -> "Unsupported media type"
              | 422 -> "Validation failed"
              | 503 -> "Service temporarily unavailable"
              | _ -> Stdlib.failwith ("unexpected Petstore error status " ^ code)
            in
            if not (Yojson.Safe.equal (member "description" response) (`String expected))
            then
              Stdlib.failwith
                (meth ^ " " ^ path ^ " -> " ^ code ^ ": unexpected response description")))))
;;
