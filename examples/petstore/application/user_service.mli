open! Base

(** Stateless application service for user accounts. It works with domain
    users and defines transaction boundaries independently of HTTP. *)
module type S = sig
  (** Effect shared by the database and repository. *)
  type 'a io

  (** Runtime database resource supplied at the application boundary. *)
  type database

  (** Adds one user without replacing an occupied username. *)
  val add
    :  database:database
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Already_exists of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Adds a complete batch atomically. *)
  val add_many
    :  database:database
    -> Domain.User.t list
    -> ( Domain.User.t list
         , [ `Already_exists of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Finds one user; absence is not a persistence error. *)
  val find
    :  database:database
    -> string
    -> (Domain.User.t option, Persistence_error.t) Result.t io

  (** Replaces the user selected by the authoritative username. *)
  val update
    :  database:database
    -> username:string
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Not_found of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Deletes one existing user. *)
  val delete
    :  database:database
    -> string
    -> (unit, [ `Not_found of string | `Persistence of Persistence_error.t ]) Result.t io

  (** Checks the demo credential through the repository. *)
  val authenticate
    :  database:database
    -> username:string
    -> password:string
    -> (bool, Persistence_error.t) Result.t io
end

(** Injects the database algebra and repository implementation at compile
    time. The resulting module is stateless. *)
module Make
    (Io : Base.Monad.S)
    (Database : Database.S with type 'a io = 'a Io.t)
    (_ :
       User_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection) :
  S with type 'a io = 'a Io.t and type database = Database.t
