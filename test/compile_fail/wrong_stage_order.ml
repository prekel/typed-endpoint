open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
open Endpoint

let invalid_declaration =
  get / "wrong-stage"
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Response" ()))
  |> accepts Request.empty
;;
