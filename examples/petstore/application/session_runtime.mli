(** Clock and token-generation port for session use cases. Inject deterministic
    implementations in tests and operating-system capabilities at the server
    composition root. *)

open! Base

(** Infrastructure capabilities selected at the composition root. *)
module type S = sig
  (** Wall-clock time in seconds since the Unix epoch, using the same time base
      as stored session expiry timestamps. *)
  val now : unit -> float

  (** Returns a fresh, non-empty, Bearer-compatible opaque token. Production
      implementations use an operating-system CSPRNG; generation failures
      return [Error] rather than falling back to predictable entropy. *)
  val token : unit -> (string, string) Result.t
end
