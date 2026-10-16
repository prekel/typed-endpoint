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

  (** Adds a complete batch atomically; only administrators are permitted. *)
  val add_many
    :  database:database
    -> actor:Domain.User.actor
    -> Domain.User.t list
    -> ( Domain.User.t list
         , [ `Forbidden
           | `Already_exists of string
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         io

  (** Finds one user; absence is not a persistence error. *)
  val find
    :  database:database
    -> string
    -> (Domain.User.t option, Persistence_error.t) Result.t io

  (** Replaces a profile for its owner or an administrator. Changing the password
      revokes all sessions in the same transaction. *)
  val update
    :  database:database
    -> actor:Domain.User.actor
    -> username:string
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Forbidden | `Not_found of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Deletes a profile and all its sessions for its owner or an administrator. *)
  val delete
    :  database:database
    -> actor:Domain.User.actor
    -> string
    -> ( unit
         , [ `Forbidden | `Not_found of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

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
        and type connection = Database.connection)
    (_ :
       Session_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection) :
  S with type 'a io = 'a Io.t and type database = Database.t
