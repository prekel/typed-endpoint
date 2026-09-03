open! Base

type t =
  [ `Unavailable
  | `Unexpected of string
  ]

let public_message = function
  | `Unavailable -> "persistence service is unavailable"
  | `Unexpected _ -> "unexpected persistence failure"
;;
