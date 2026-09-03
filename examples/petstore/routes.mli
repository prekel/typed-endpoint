open! Base
open Typed_endpoint

(** Credentials accepted by the example authorization guard. *)
type auth =
  { bearer_token : string
  ; api_key : string
  }

(** Reads demo credentials from [PETSTORE_BEARER_TOKEN] and
    [PETSTORE_API_KEY], falling back to local-development values. *)
val auth_from_env : unit -> auth

(** OpenAPI document metadata used by every server entrypoint. *)
val openapi_config : Openapi.Config.t

(** Builds the complete official Swagger Petstore v3 route surface for any
    typed-endpoint backend. DTO/domain conversion and HTTP status selection
    happen inside these routes; injected services remain framework-independent. *)
module Make (B : Backend.S) : sig
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Compiles API routes plus runtime-only health, OpenAPI, and Swagger UI
      endpoints. Raises if the static route contract is inconsistent. *)
  val compile : auth:auth -> Services.t -> Endpoint.Dsl.Compiled.t
end
