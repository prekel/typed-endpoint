open! Base

(** Demo credentials consumed by controller guards. A real application would
    inject a token verifier instead of storing accepted secrets here. *)
type t =
  { bearer_token : string
  ; api_key : string
  }

(** Reads credentials from [PETSTORE_BEARER_TOKEN] and [PETSTORE_API_KEY], with
    local-development defaults. *)
val from_env : unit -> t
