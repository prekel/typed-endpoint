open! Base
module App = Petstore_app.Routes.Make (Typed_endpoint_dream)
module Dsl = App.Endpoint.Dsl

let () =
  let service = Petstore_app.Pet_service.create () in
  let compiled = App.compile ~auth:(Petstore_app.Routes.auth_from_env ()) service in
  Dsl.Compiled.app compiled |> Typed_endpoint_dream.router |> Dream.run
;;
