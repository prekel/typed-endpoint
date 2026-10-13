open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
open Endpoint

let route =
  get / "compile-valid"
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Response" ()))
  ==> fun ok () () -> respond ok "ok"
;;

let compiled =
  compile_exn
    [ Group.make_with_context
        ~context:(Context.return ())
        ~description:"Valid group"
        [ route ]
    ]
;;
