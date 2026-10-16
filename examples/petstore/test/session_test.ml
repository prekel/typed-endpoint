open! Base
module B = Typed_endpoint_testing
module Database = Petstore_app.Database_memory.Make (B.Io)

module Runtime = struct
  let clock = ref 100.
  let sequence = ref 0
  let now () = !clock

  let token () =
    Int.incr sequence;
    Ok ("token-" ^ Int.to_string !sequence)
  ;;
end

module App =
  Petstore_app.Routes.Make (B) (Database) (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)
    (Database.Session_repository)
    (Runtime)

module Common = Petstore_app.Controller_context.Make (B) (App.Sessions)
module E = Common.Endpoint
open E

let database = Database.create ()
let auth = Petstore_app.Auth.{ bearer_token = "demo"; api_key = "key" }
let routes = App.compile ~auth ~database () |> App.Endpoint.Compiled.app
let request = B.Client.call routes
let json = [ "content-type", "application/json" ]
let assert_status status response = assert (B.Response.status response = status)

let token response =
  Yojson.Safe.Util.to_string (B.Response.json response |> Result.ok_or_failwith)
;;

let auth_header token = [ "authorization", "bEaReR " ^ token ]

let login username password =
  request
    ~headers:json
    ~body:
      (Yojson.Safe.to_string
         (`Assoc [ "username", `String username; "password", `String password ]))
    `POST
    "/user/login"
;;

let whoami =
  get / "whoami"
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Identity" ()))
  ==> fun ok context () ->
  let identity = Typed_endpoint.Principal.identity (Common.Secured.principal context) in
  respond ok (identity.subject ^ ":" ^ Option.value identity.session_id ~default:"demo")
;;

let identity_routes =
  compile_exn
    [ Group.make_with_context
        ~context:(Common.session ~auth database)
        ~description:"Identity"
        [ whoami ]
    ]
  |> Compiled.app
;;

let identity token =
  B.Client.call identity_routes ~headers:(auth_header token) `GET "/whoami"
;;

let () =
  List.iter [ "alice"; "bob" ] ~f:(fun username ->
    let body =
      Yojson.Safe.to_string
        (`Assoc [ "username", `String username; "password", `String "secret" ])
    in
    assert_status 200 (request ~headers:json ~body `POST "/user"));
  let alice_response = login "alice" "secret" in
  assert_status 200 alice_response;
  let alice = token alice_response in
  let bob_response = login "bob" "secret" in
  assert_status 200 bob_response;
  let bob = token bob_response in
  let again_response = login "alice" "secret" in
  assert_status 200 again_response;
  let again = token again_response in
  assert ((not (String.equal alice bob)) && not (String.equal alice again));
  assert (String.equal (B.Response.body (identity alice)) ("alice:" ^ alice));
  assert (String.equal (B.Response.body (identity bob)) ("bob:" ^ bob));
  assert_status 400 (login "alice" "wrong");
  assert_status 400 (login "" "secret");
  assert_status 400 (login "alice" "");
  List.iter
    [ {|{}|}; {|{"username":"alice"}|}; {|{"password":"secret"}|} ]
    ~f:(fun body -> assert_status 400 (request ~headers:json ~body `POST "/user/login"));
  assert_status 200 (request ~headers:(auth_header alice) `POST "/user/logout");
  assert_status 401 (identity alice);
  assert_status 401 (request ~headers:(auth_header alice) `POST "/user/logout");
  assert_status 200 (identity bob);
  assert_status 200 (identity again);
  assert_status 401 (request `POST "/user/logout");
  assert_status 401 (identity "missing");
  assert_status 200 (request ~headers:(auth_header "demo") `POST "/user/logout");
  assert_status 200 (identity "demo");
  Runtime.clock := 3700.;
  assert_status 401 (identity bob);
  assert_status 401 (identity again);
  assert_status 401 (request ~headers:(auth_header bob) `POST "/user/logout");
  assert_status 200 (identity "demo");
  let empty_auth = { auth with api_key = "" } in
  let empty_routes =
    App.compile ~auth:empty_auth ~database () |> App.Endpoint.Compiled.app
  in
  assert_status
    401
    (B.Client.call empty_routes ~headers:[ "api_key", "" ] `GET "/store/inventory");
  let document =
    App.Endpoint.Compiled.openapi
      ~config:Petstore_app.Routes.openapi_config
      (App.compile ~auth ~database ())
  in
  let open Yojson.Safe.Util in
  let login_contract =
    document |> member "paths" |> member "/user/login" |> member "post"
  in
  assert (login_contract |> member "parameters" |> Yojson.Safe.equal `Null);
  assert (
    login_contract
    |> member "responses"
    |> member "200"
    |> member "headers"
    |> Yojson.Safe.equal `Null);
  let schemas = document |> member "components" |> member "schemas" in
  assert (
    schemas
    |> member "LoginRequest"
    |> member "required"
    |> to_list
    |> List.map ~f:to_string
    |> List.sort ~compare:String.compare
    |> List.equal String.equal [ "password"; "username" ]);
  assert (
    schemas
    |> member "User"
    |> member "properties"
    |> member "password"
    |> Yojson.Safe.equal `Null);
  assert (
    not
      (schemas
       |> member "UserCreate"
       |> member "properties"
       |> member "password"
       |> Yojson.Safe.equal `Null));
  assert (String.equal (document |> member "openapi" |> to_string) "3.1.0");
  assert (
    String.is_substring
      (document |> member "info" |> member "title" |> to_string)
      ~substring:"3.1")
;;

module Broken_runtime = struct
  let now = Runtime.now
  let token () = Error "entropy unavailable"
end

module Broken =
  Petstore_app.Routes.Make (B) (Database) (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)
    (Database.Session_repository)
    (Broken_runtime)

let () =
  let broken = Broken.compile ~auth ~database () |> Broken.Endpoint.Compiled.app in
  let response =
    B.Client.call
      broken
      ~headers:json
      ~body:{|{"username":"alice","password":"secret"}|}
      `POST
      "/user/login"
  in
  assert_status 503 response;
  assert (
    not (String.is_substring (B.Response.body response) ~substring:"entropy unavailable"));
  let before = !Runtime.sequence in
  ignore (login "alice" "wrong" : B.response);
  assert (!Runtime.sequence = before)
;;

module Collision_runtime = struct
  let now = Runtime.now
  let token () = Ok "collision"
end

module Collisions =
  Petstore_app.Session_service.Make (B.Io) (Database) (Database.User_repository)
    (Database.Session_repository)
    (Collision_runtime)

let result_exn result =
  Result.map_error result ~f:Petstore_app.Persistence_error.public_message
  |> Result.ok_or_failwith
;;

let () =
  let first =
    Collisions.login ~database ~username:"alice" ~password:"secret" |> result_exn
  in
  assert (Option.is_some first);
  let second = Collisions.login ~database ~username:"bob" ~password:"secret" in
  assert (Result.is_error second);
  let saved = Collisions.find ~database "collision" |> result_exn |> Option.value_exn in
  assert (String.equal saved.username "alice")
;;

let () =
  let previous = Stdlib.Sys.getenv_opt "PETSTORE_API_KEY" in
  Exn.protect
    ~f:(fun () ->
      Unix.putenv "PETSTORE_API_KEY" "";
      let failed =
        try
          ignore (Petstore_app.Auth.from_env_exn () : Petstore_app.Auth.t);
          false
        with
        | Invalid_argument _ -> true
      in
      assert failed)
    ~finally:(fun () ->
      Unix.putenv "PETSTORE_API_KEY" (Option.value previous ~default:"demo-key"))
;;

let () =
  let get_properties schema_name =
    let compiled = App.compile ~auth ~database () in
    let document = App.Endpoint.Compiled.openapi compiled in
    let open Yojson.Safe.Util in
    document
    |> member "components"
    |> member "schemas"
    |> member schema_name
    |> member "properties"
  in
  let open Yojson.Safe.Util in
  let pet_id = get_properties "Pet" |> member "id" in
  assert (pet_id |> member "minimum" |> to_int = 1);
  assert (pet_id |> member "maximum" |> to_int = Int.max_value);
  let quantity = get_properties "Order" |> member "quantity" in
  let maximum = Int64.(to_int_exn (min (of_int Int.max_value) 2147483647L)) in
  assert (quantity |> member "maximum" |> to_int = maximum);
  List.iter [ -1; 0 ] ~f:(fun value ->
    assert (
      Result.is_error
        (Petstore_app.Dto.Order.of_yojson (`Assoc [ "quantity", `Int value ]))));
  if Int.max_value > maximum then
    assert (
      Result.is_error
        (Petstore_app.Dto.Order.of_yojson (`Assoc [ "quantity", `Int (maximum + 1) ])));
  assert (
    Result.is_error
      (Petstore_app.Dto.Pet.of_yojson
         (`Assoc
             [ "id", `Intlit "9223372036854775807"
             ; "name", `String "pet"
             ; "photoUrls", `List []
             ])));
  List.iter [ "0x10"; "1_000" ] ~f:(fun value ->
    assert (Result.is_error (Petstore_app.Http_parameter.Pet_id.of_string value));
    assert (Result.is_error (Petstore_app.Http_parameter.Order_id.of_string value));
    assert (Result.is_error (Petstore_app.Http_parameter.Page.of_string value));
    assert (Result.is_error (Petstore_app.Http_parameter.Limit.of_string value)))
;;

let () =
  let module Auth = Petstore_app.Auth in
  List.iter [ "Bearer demo"; "bearer demo"; "bEaReR   demo" ] ~f:(fun value ->
    assert (Option.equal String.equal (Auth.bearer_token value) (Some "demo")));
  assert (
    Option.equal String.equal (Auth.bearer_token "Bearer aB-._~+/==") (Some "aB-._~+/=="));
  List.iter
    [ "Bearer"
    ; "Bearer "
    ; "Bearer   "
    ; "Bearer\tdemo"
    ; "Bearer demo "
    ; "Bearer demo\000"
    ; "Bearer demo:token"
    ; "Bearer ="
    ; "Bearer a=b"
    ]
    ~f:(fun value -> assert (Option.is_none (Auth.bearer_token value)));
  assert_status
    200
    (request
       ~headers:[ "authorization", "bEaReR   demo" ]
       `GET
       "/pet/findByStatus?status=available");
  assert_status
    401
    (request
       ~headers:[ "authorization", "bearer   DEMO" ]
       `GET
       "/pet/findByStatus?status=available")
;;
