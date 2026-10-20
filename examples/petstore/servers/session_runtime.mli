(** Unix clock and entropy implementation of the application session-runtime
    port. Server composition roots select this module; application services
    depend only on the corresponding port. *)

open! Base

(** System clock, in seconds since the Unix epoch. *)
val now : unit -> float

(** A 64-character lowercase hexadecimal token from 256 bits read from
    [/dev/urandom]. Opening or reading the entropy source returns [Error] with
    the internal diagnostic rather than generating a fallback token. *)
val token : unit -> (string, string) Result.t
