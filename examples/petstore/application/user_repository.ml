open! Base

module type S = sig
  type 'a io
  type t

  type error =
    [ `Not_found of string
    | `Persistence of Persistence_error.t
    ]

  type create_error =
    [ `Already_exists of string
    | `Persistence of Persistence_error.t
    ]

  val add : t -> Domain.User.t -> (Domain.User.t, create_error) Result.t io
  val add_many : t -> Domain.User.t list -> (Domain.User.t list, create_error) Result.t io
  val find : t -> string -> (Domain.User.t option, Persistence_error.t) Result.t io
  val update : t -> username:string -> Domain.User.t -> (Domain.User.t, error) Result.t io
  val delete : t -> string -> (unit, error) Result.t io

  val authenticate
    :  t
    -> username:string
    -> password:string
    -> (bool, Persistence_error.t) Result.t io
end
