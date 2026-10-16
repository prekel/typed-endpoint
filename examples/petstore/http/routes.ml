open! Base
open Typed_endpoint

type auth = Auth.t =
  { bearer_token : string
  ; api_key : string
  }

let auth_from_env_exn = Auth.from_env_exn

let openapi_config =
  Openapi.Config.v
    ~title:"Swagger Petstore - OpenAPI 3.1"
    ~version:"1.0.29-SNAPSHOT"
    ~description:
      "A typed-endpoint implementation of Swagger Petstore v3 with session-based login"
    ~servers:[ Openapi.Server.v ~url:"http://localhost:8080" () ]
    ()
;;

module Make
    (B : Backend.S)
    (Database : Database.S with type 'a io = 'a B.io)
    (Pet_repository :
       Pet_repository.S
       with type 'a io = 'a B.io
        and type connection = Database.connection)
    (Order_repository :
       Order_repository.S
       with type 'a io = 'a B.io
        and type connection = Database.connection)
    (User_repository :
       User_repository.S
       with type 'a io = 'a B.io
        and type connection = Database.connection)
    (Session_repository :
       Session_repository.S
       with type 'a io = 'a B.io
        and type connection = Database.connection)
    (Session_runtime : Session_runtime.S) =
struct
  module Endpoint = Typed_endpoint.Make (B)
  module Pets = Pet_service.Make (B.Io) (Database) (Pet_repository)
  module Orders = Order_service.Make (B.Io) (Database) (Pet_repository) (Order_repository)

  module Users =
    User_service.Make (B.Io) (Database) (User_repository) (Session_repository)

  module Sessions =
    Session_service.Make (B.Io) (Database) (User_repository) (Session_repository)
      (Session_runtime)

  module Pet_controller = Pet_controller.Make (B) (Pets) (Sessions)
  module Store_controller = Store_controller.Make (B) (Pets) (Orders) (Sessions)
  module User_controller = User_controller.Make (B) (Users) (Sessions)
  open Endpoint

  let openapi_route compiled =
    Unsafe.route ~meth:`GET ~path:"/openapi.json" ~handler:(fun _request ->
      B.respond_json ~pretty:true (Compiled.openapi ~config:openapi_config compiled))
  ;;

  let docs_page (path, html) =
    Unsafe.route ~meth:`GET ~path ~handler:(fun _request -> B.respond_html html)
  ;;

  let health =
    Unsafe.route ~meth:`GET ~path:"/health" ~handler:(fun _request ->
      B.respond_json (`Assoc [ "status", `String "ok" ]))
  ;;

  let compile ?(interceptors = []) ~auth ~database () =
    let api =
      Pet_controller.groups ~auth ~database
      @ Store_controller.groups ~auth ~database
      @ User_controller.groups ~auth ~database
    in
    let compiled = compile_exn api in
    let runtime =
      Group.make
        ~description:"Runtime endpoints"
        (openapi_route compiled :: health :: List.map Api_docs.pages ~f:docs_page)
    in
    compile_exn ~interceptors (api @ [ runtime ])
  ;;
end
