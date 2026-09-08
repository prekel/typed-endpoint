open! Base

(** Process-owned database resource and its scoped connections. This port
    keeps transaction management in the application layer without exposing a
    concrete driver such as Caqti. *)
module type S = sig
  (** Effect shared with repositories and application services. *)
  type 'a io

  (** Long-lived database handle, normally a connection pool. *)
  type t

  (** Connection valid only during a callback below. A callback must not retain
      the value for use after it returns. *)
  type connection

  (** Runs [f] with one connection but without starting an application
      transaction. Infrastructure failures are converted with [on_error]. *)
  val with_connection
    :  t
    -> on_error:(Persistence_error.t -> 'error)
    -> f:(conn:connection -> ('a, 'error) Result.t io)
    -> ('a, 'error) Result.t io

  (** Runs [f] in one transaction. [Ok] commits and [Error] rolls back.
      Acquisition, commit, or rollback failures are converted with [on_error];
      a rollback failure takes precedence over the callback error. *)
  val transaction
    :  t
    -> on_error:(Persistence_error.t -> 'error)
    -> f:(conn:connection -> ('a, 'error) Result.t io)
    -> ('a, 'error) Result.t io
end
