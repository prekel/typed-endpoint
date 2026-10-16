open! Base
open Typed_endpoint
module E = Make (Typed_endpoint_testing)
open E

let invalid =
  get
  / "collection"
  /! query_arg
       "values"
       (Query.repeated ~description:"Values" (Parameter.int ~description:"Value" ()))
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Result" ()))
  ==> fun (value : int) ok () () -> respond ok (Int.to_string value)
;;
