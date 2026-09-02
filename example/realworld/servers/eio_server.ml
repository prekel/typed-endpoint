open! Base

module Request = struct
  type t = Typed_endpoint_eio.req

  let header = Typed_endpoint_eio.Request.header
end

module App = Realworld_app.Routes.Make (Typed_endpoint_eio) (Request)

let () =
  let compiled = Realworld_app.Article_service.seeded () |> App.compile in
  let server = compiled |> App.Endpoint.D.Compiled.app |> Typed_endpoint_eio.server in
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
