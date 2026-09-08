open! Base

module type S = sig
  type 'a io
  type connection

  type error =
    [ `Not_found of int
    | `Persistence of Persistence_error.t
    ]

  type place_error =
    [ `Already_exists of int
    | `Persistence of Persistence_error.t
    ]

  val place
    :  conn:connection
    -> ?id:int
    -> Domain.Order.attributes
    -> (Domain.Order.t, place_error) Result.t io

  val find
    :  conn:connection
    -> int
    -> (Domain.Order.t option, Persistence_error.t) Result.t io

  val delete : conn:connection -> int -> (unit, error) Result.t io
end
