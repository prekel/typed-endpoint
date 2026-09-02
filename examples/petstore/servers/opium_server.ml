open! Base
module App = Petstore_app.Routes.Make (Typed_endpoint_opium)
module Dsl = App.Endpoint.Dsl

let () =
  let service = Petstore_app.Pet_service.create () in
  let compiled = App.compile ~auth:(Petstore_app.Routes.auth_from_env ()) service in
  Opium.App.empty
  |> Dsl.Compiled.app compiled
  |> Opium.App.port 8080
  |> Opium.App.run_command
;;
