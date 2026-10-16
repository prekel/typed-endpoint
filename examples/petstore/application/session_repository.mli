open! Base

(** Stateless session storage using transaction-scoped connections. *)
module type S = sig
  type 'a io
  type connection

  (** [false] reports an existing token without overwriting its session. *)
  val add : conn:connection -> Domain.Session.t -> (bool, Persistence_error.t) Result.t io

  val find
    :  conn:connection
    -> string
    -> (Domain.Session.t option, Persistence_error.t) Result.t io

  val remove : conn:connection -> string -> (unit, Persistence_error.t) Result.t io

  (** Removes every session of a user within the caller's transaction. *)
  val remove_by_username
    :  conn:connection
    -> username:string
    -> (unit, Persistence_error.t) Result.t io
end
