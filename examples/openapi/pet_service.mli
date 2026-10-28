open! Base

(** Stateless lookup; storage is supplied explicitly. *)
val find : pets:Domain.t list -> int64 -> Domain.t option
