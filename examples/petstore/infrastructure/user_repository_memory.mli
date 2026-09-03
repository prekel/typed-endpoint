open! Base

(** In-memory adapter for the user repository port. Bulk insertion is atomic. *)
module Make (Io : Base.Monad.S) : sig
  include User_repository.S with type 'a io = 'a Io.t

  (** Creates an empty isolated repository. *)
  val create : unit -> t
end
