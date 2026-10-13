open! Base

(* Infrastructure capabilities selected at the composition root. *)
module type S = sig
  val now : unit -> float

  (* Returns a new opaque token from an operating-system CSPRNG. *)
  val token : unit -> (string, string) Result.t
end
