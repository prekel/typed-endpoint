open! Base
open Typed_endpoint

type auth =
  { bearer_token : string
  ; api_key : string
  }

val auth_from_env : unit -> auth
val openapi_config : Openapi.Config.t

module Make (B : Backend.S) : sig
  module Endpoint : module type of Typed_endpoint.Make (B)

  val compile : auth:auth -> Pet_service.t -> Endpoint.Dsl.Compiled.t
end
