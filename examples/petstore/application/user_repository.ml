open! Base

module type S = sig
  type 'a io
  type connection

  type error =
    [ `Not_found of string
    | `Persistence of Persistence_error.t
    ]

  type create_error =
    [ `Already_exists of string
    | `Persistence of Persistence_error.t
    ]

  val add : conn:connection -> Domain.User.t -> (Domain.User.t, create_error) Result.t io

  val add_many
    :  conn:connection
    -> Domain.User.t list
    -> (Domain.User.t list, create_error) Result.t io

  val find
    :  conn:connection
    -> string
    -> (Domain.User.t option, Persistence_error.t) Result.t io

  val update
    :  conn:connection
    -> username:string
    -> Domain.User.t
    -> (Domain.User.t, error) Result.t io

  val delete : conn:connection -> string -> (unit, error) Result.t io

  val authenticate
    :  conn:connection
    -> username:string
    -> password:string
    -> (bool, Persistence_error.t) Result.t io
end
