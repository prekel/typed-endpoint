open! Base

(** In-memory adapter for the order repository port. *)
module Make (Io : Base.Monad.S) : sig
  include Order_repository.S with type 'a io = 'a Io.t

  (** Creates an empty isolated repository. *)
  val create : unit -> t
end
