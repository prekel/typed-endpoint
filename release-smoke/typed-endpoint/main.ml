open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
open Endpoint

let route =
  get / "health"
  |> documented ~operation_id:"health"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Health status" ()))
  |> handle @@ fun ok () -> respond ok "ok"
;;

let routes =
  compile_exn [ Group.make ~description:"Release smoke" [ route ] ] |> Compiled.app
;;

let () = ignore routes
