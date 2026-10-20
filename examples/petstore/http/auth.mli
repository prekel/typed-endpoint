(** Development authentication configuration and Bearer-header parsing.
    Login sessions are resolved separately through the application service;
    this module does not perform credential verification or database access. *)

open! Base

(** Independent development credentials accepted alongside login sessions. *)
type t =
  { bearer_token : string
  ; api_key : string
  }

(** Reads credentials from [PETSTORE_BEARER_TOKEN] and [PETSTORE_API_KEY], with
    local-development defaults. Raises [Invalid_argument] for an empty API key. *)
val from_env_exn : unit -> t

(** Parses the case-insensitive scheme, one or more SP separators, and a
    non-empty RFC 6750 token. Token bytes remain case-sensitive. *)
val bearer_token : string -> string option
