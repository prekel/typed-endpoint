open! Base
module Petstore_principal = Principal
open Typed_endpoint

(** Shared controller policies. Context composition injects a controller only
    after its guard succeeds, and also supplies matching OpenAPI security
    metadata to every route in the group. *)
module Make (B : Backend.S) : sig
  (** Endpoint instance whose context types are returned below. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  module Secured : sig
    (** Protected request context. [dependency] remains the statically selected
        application value; principal and request ID are request-scoped. *)
    type 'a t = private
      { dependency : 'a
      ; principal : Petstore_principal.t
      ; request_id : string option
      }

    val dependency : 'a t -> 'a
    val principal : _ t -> Petstore_principal.t
    val request_id : _ t -> string option
  end

  (** Requires the official OAuth credentials and injects [dependency]. *)
  val pet_oauth : auth:Auth.t -> 'a -> 'a Secured.t Endpoint.Context.t

  (** Accepts either the official OAuth credentials or API key. *)
  val pet_lookup : auth:Auth.t -> 'a -> 'a Secured.t Endpoint.Context.t

  (** Requires the official API key and injects [dependency]. *)
  val api_key : auth:Auth.t -> 'a -> 'a Secured.t Endpoint.Context.t

  (** Injects [dependency] without an authorization guard. *)
  val public : 'a -> 'a Endpoint.Context.t

  (** Stable JSON mapping used by all controller groups. *)
  val decode_errors : Endpoint.Decode_error_response.t
end
