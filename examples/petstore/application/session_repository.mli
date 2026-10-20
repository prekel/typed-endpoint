(** Persistence port for revocable login sessions. Token uniqueness and bulk
    revocation participate in the transaction opened by the application service. *)

open! Base

(** Stateless session storage using transaction-scoped connections. *)
module type S = sig
  (** Effect shared with the database and session application service. *)
  type 'a io

  (** Connection valid only within the calling service's database callback. *)
  type connection

  (** Inserts a session by token. [Ok false] reports a collision without
      overwriting the stored session; expiry is checked by the service. *)
  val add : conn:connection -> Domain.Session.t -> (bool, Persistence_error.t) Result.t io

  (** Looks up a token without filtering expired sessions. Missing tokens return
      [Ok None]; the service applies its clock before accepting the identity. *)
  val find
    :  conn:connection
    -> string
    -> (Domain.Session.t option, Persistence_error.t) Result.t io

  (** Revokes a token. Removing an absent token succeeds without changing state. *)
  val remove : conn:connection -> string -> (unit, Persistence_error.t) Result.t io

  (** Removes every session of a user within the caller's transaction. *)
  val remove_by_username
    :  conn:connection
    -> username:string
    -> (unit, Persistence_error.t) Result.t io
end
