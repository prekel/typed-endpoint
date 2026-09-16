open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
open Endpoint

let route =
  get / "wrong-status"
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Response" ()))
  |> handle @@ fun (not_found : ([ `Not_found ], string) Response.case) () ->
     respond not_found "missing"
;;
