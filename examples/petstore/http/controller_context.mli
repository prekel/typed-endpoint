open! Base
open Typed_endpoint

(** Shared controller policies. Context composition injects a controller only
    after its guard succeeds, and also supplies matching OpenAPI security
    metadata to every route in the group. *)
module Make (B : Backend.S) : sig
  (** Endpoint instance whose context types are returned below. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Requires the official OAuth credentials and injects [dependency]. *)
  val pet_oauth : auth:Auth.t -> 'a -> 'a Endpoint.Dsl.Context.t

  (** Accepts either the official OAuth credentials or API key. *)
  val pet_lookup : auth:Auth.t -> 'a -> 'a Endpoint.Dsl.Context.t

  (** Requires the official API key and injects [dependency]. *)
  val api_key : auth:Auth.t -> 'a -> 'a Endpoint.Dsl.Context.t

  (** Injects [dependency] without an authorization guard. *)
  val public : 'a -> 'a Endpoint.Dsl.Context.t

  (** Stable JSON mapping used by all controller groups. *)
  val decode_errors : Endpoint.Dsl.Decode_error_response.t
end
