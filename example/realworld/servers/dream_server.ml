open! Base

module Request = struct
  type t = Typed_endpoint_dream.req

  let header = Dream.header
end

module App = Realworld_app.Routes.Make (Typed_endpoint_dream) (Request)

let () =
  let compiled = Realworld_app.Article_service.seeded () |> App.compile in
  compiled
  |> App.Endpoint.D.Compiled.app
  |> Typed_endpoint_dream.router
  |> Dream.run ~interface:"0.0.0.0" ~port:8080
;;
