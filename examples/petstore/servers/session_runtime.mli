open! Base

(** System clock, in seconds since the Unix epoch. *)
val now : unit -> float

(** A hex token from 256 bits of operating-system entropy. *)
val token : unit -> (string, string) Result.t
