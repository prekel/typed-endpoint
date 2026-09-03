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

module Make_with_services
    (B : Backend.S)
    (Pets : Pet_service.S with type 'a io = 'a B.io)
    (Orders : Order_service.S with type 'a io = 'a B.io)
    (Users : User_service.S with type 'a io = 'a B.io) =
struct
  module Endpoint = Typed_endpoint.Make (B)
  module Pet_controller = Pet_controller.Make (B) (Pets)
  module Store_controller = Store_controller.Make (B) (Pets) (Orders)
  module User_controller = User_controller.Make (B) (Users)
  open Endpoint.Dsl

  type services = (Pets.t, Orders.t, Users.t) Services.t

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

  let compile ~auth services =
    let pets = Services.pets services in
    let orders = Services.orders services in
    let users = Services.users services in
    let pet_controller = Pet_controller.create ~pets in
    let store_controller = Store_controller.create ~pets ~orders in
    let user_controller = User_controller.create ~users in
    let api =
      Pet_controller.groups ~auth pet_controller
      @ Store_controller.groups ~auth store_controller
      @ User_controller.groups user_controller
    in
    let compiled = compile_exn api in
    let runtime =
      Group.make
        ~description:"Runtime endpoints"
        (openapi_route compiled :: health :: List.map Api_docs.pages ~f:docs_page)
    in
    compile_exn (api @ [ runtime ])
  ;;
end

module Make (B : Backend.S) = struct
  module Services = Memory_services.Make (B.Io)
  include Make_with_services (B) (Services.Pets) (Services.Orders) (Services.Users)
end
