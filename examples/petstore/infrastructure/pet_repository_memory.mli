open! Base

(** In-memory adapter for the pet repository port. Each functor application
    owns no global state; values returned by [create] are isolated stores. *)
module Make (Io : Base.Monad.S) : sig
  include Pet_repository.S with type 'a io = 'a Io.t

  (** Creates an empty isolated repository. *)
  val create : unit -> t
end
