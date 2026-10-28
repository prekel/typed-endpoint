open! Base

(** Transport-independent read model used by the example service. *)
type t =
  { id : int64
  ; name : string
  }
