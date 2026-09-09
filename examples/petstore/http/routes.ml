open! Base
open Typed_endpoint

type auth = Auth.t =
  { bearer_token : string
  ; api_key : string
  }

let auth_from_env = Auth.from_env

let openapi_config =
  Openapi.Config.v
    ~title:"Swagger Petstore - OpenAPI 3.0"
    ~version:"1.0.29-SNAPSHOT"
    ~description:
      "A typed-endpoint implementation of the complete Swagger Petstore v3 route surface"
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
        and type connection = Database.connection) =
struct
  module Endpoint = Typed_endpoint.Make (B)
  module Pets = Pet_service.Make (B.Io) (Database) (Pet_repository)
  module Orders = Order_service.Make (B.Io) (Database) (Pet_repository) (Order_repository)
  module Users = User_service.Make (B.Io) (Database) (User_repository)
  module Pet_controller = Pet_controller.Make (B) (Pets)
  module Store_controller = Store_controller.Make (B) (Pets) (Orders)
  module User_controller = User_controller.Make (B) (Users)
  open Endpoint.Dsl

  let openapi_route compiled =
    Unsafe.route ~meth:B.get ~path:"/openapi.json" ~handler:(fun _request ->
      B.respond_json (Compiled.openapi ~config:openapi_config compiled))
  ;;

  let docs_page (path, html) =
    Unsafe.route ~meth:B.get ~path ~handler:(fun _request -> B.respond_html html)
  ;;

  let health =
    Unsafe.route ~meth:B.get ~path:"/health" ~handler:(fun _request ->
      B.respond_json (`Assoc [ "status", `String "ok" ]))
  ;;

  let compile ?(interceptors = []) ~auth ~database () =
    let api =
      Pet_controller.groups ~auth ~database
      @ Store_controller.groups ~auth ~database
      @ User_controller.groups ~database
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
