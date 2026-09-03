open! Base

(** Application service for user accounts. It depends on a repository port,
    not on a concrete database or HTTP representation. *)
module type S = sig
  (** Effect shared with the injected repository. *)
  type 'a io

  (** User service instance. *)
  type t

  (** Adds one user without replacing an occupied username. *)
  val add
    :  t
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Already_exists of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Adds a complete batch atomically. *)
  val add_many
    :  t
    -> Domain.User.t list
    -> ( Domain.User.t list
         , [ `Already_exists of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Finds one user; absence is not a persistence error. *)
  val find : t -> string -> (Domain.User.t option, Persistence_error.t) Result.t io

  (** Replaces the user selected by the authoritative username. *)
  val update
    :  t
    -> username:string
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Not_found of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Deletes one existing user. *)
  val delete
    :  t
    -> string
    -> (unit, [ `Not_found of string | `Persistence of Persistence_error.t ]) Result.t io

  (** Checks the demo credential through the repository. *)
  val authenticate
    :  t
    -> username:string
    -> password:string
    -> (bool, Persistence_error.t) Result.t io
end

(** Injects a repository implementation into the user application service. *)
module Make
    (Io : Base.Monad.S)
    (Repository : User_repository.S with type 'a io = 'a Io.t) : sig
  include S with type 'a io = 'a Io.t

  (** Creates a user service using the supplied repository instance. *)
  val create : repository:Repository.t -> t
end
