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

let collection_route =
  get
  / "valid-collection"
  /! query_arg
       "values"
       (Query.repeated ~description:"Values" (Parameter.int ~description:"Value" ()))
  /? query_arg
       "tags"
       (Query.csv ~description:"Tags" (Parameter.string ~description:"Tag" ()))
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Result" ()))
  ==> fun values tags ok () () ->
  let tags = Option.value tags ~default:[] in
  respond ok (Int.to_string (List.length values + List.length tags))
;;

let shared_scalar = arg "n" (Parameter.int ~description:"Number" ())

let mixed_route =
  get
  / "mixed"
  /: shared_scalar
  /! shared_scalar
  /! query_arg
       "values"
       (Query.repeated ~description:"Values" (Parameter.int ~description:"Value" ()))
  /? shared_scalar
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Result" ()))
  ==> fun path query values optional ok () () ->
  respond
    ok
    (Int.to_string (path + query + List.length values + Option.value optional ~default:0))
;;
