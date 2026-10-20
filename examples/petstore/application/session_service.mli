(** Login, session lookup, and logout over the user and session repository ports.
    The service owns database scopes and uses an explicitly supplied clock and
    token generator. *)

open! Base

(** Stateless session use cases; login and logout define transaction boundaries. *)
module type S = sig
  (** Effect shared by the database and both repository ports. *)
  type 'a io

  (** Runtime database resource supplied separately to every use case. *)
  type database

  (** Authenticates and creates an independent one-hour session in one
      transaction. [Ok None] means invalid credentials. Token generation is
      attempted at most three times; entropy failures, empty tokens, and exhausted
      retries return an unexpected persistence error. *)
  val login
    :  database:database
    -> username:string
    -> password:string
    -> (Domain.Session.t option, Persistence_error.t) Result.t io

  (** Reads within a connection scope without starting a transaction. Missing
      tokens and sessions whose expiry is at or before [now ()] return [Ok None].
      Lookup does not remove expired records. *)
  val find
    :  database:database
    -> string
    -> (Domain.Session.t option, Persistence_error.t) Result.t io

  (** Removes a stored token in one transaction. [Ok true] means a live session
      was revoked; absent or expired sessions return [Ok false]. Expired records
      are still removed when present. *)
  val logout : database:database -> string -> (bool, Persistence_error.t) Result.t io
end

(** All dependencies, including clock and entropy, are selected statically. *)
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
        and type connection = Database.connection)
    (_ : Session_runtime.S) : S with type 'a io = 'a Io.t and type database = Database.t
