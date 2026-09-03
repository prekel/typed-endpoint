open! Base
module App = Petstore_app.Routes.Make (Typed_endpoint_eio)
module Dsl = App.Endpoint.Dsl

let () =
  let services = App.Services.create () in
  let compiled = App.compile ~auth:(Petstore_app.Routes.auth_from_env ()) services in
  let server = Dsl.Compiled.app compiled |> Typed_endpoint_eio.server in
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let socket =
    Eio.Net.listen
      ~sw
      ~backlog:128
      (Eio.Stdenv.net env)
      (`Tcp (Eio.Net.Ipaddr.V4.any, 8080))
  in
  Cohttp_eio.Server.run ~on_error:Stdlib.raise socket server
;;
