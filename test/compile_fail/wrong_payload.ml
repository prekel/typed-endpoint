open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
open Endpoint

let route =
  get / "wrong-payload"
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Response" ()))
  |> handle @@ fun ok () -> respond ok 42
;;
