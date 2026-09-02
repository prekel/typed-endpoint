open! Base

module Request = struct
  type t = Typed_endpoint_opium.req

  let header request name = Cohttp.Header.get (Opium.Std.Request.headers request) name
end

module App = Realworld_app.Routes.Make (Typed_endpoint_opium) (Request)

let () =
  let compiled = Realworld_app.Article_service.seeded () |> App.compile in
  Opium.App.empty
  |> App.Endpoint.D.Compiled.app compiled
  |> Opium.App.port 8080
  |> Opium.App.run_command
;;
