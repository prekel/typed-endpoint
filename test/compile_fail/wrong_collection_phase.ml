open! Base
open Typed_endpoint
module E = Make (Typed_endpoint_testing)
open E

let invalid =
  get
  / "collection"
  /! query_arg
       "tags"
       (Query.csv ~description:"Tags" (Parameter.string ~description:"Tag" ()))
  |> fun uri -> uri / "late-path"
;;
