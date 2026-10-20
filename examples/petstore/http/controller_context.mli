(** Request contexts shared by Petstore controllers. Guards authenticate before
    the database dependency reaches a handler, and their security and error
    declarations are included in each protected route's OpenAPI contract. *)

open! Base

(** Principal type shared with authorization guards and route contexts. *)
module Petstore_principal = Principal

open Typed_endpoint

(** Shared controller policies. Context composition injects a controller only
    after its guard succeeds, and also supplies matching OpenAPI security
    metadata to every route in the group. *)
module Make (B : Backend.S) (Sessions : Session_service.S with type 'a io = 'a B.io) : sig
  (** Endpoint instance whose context types are returned below. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Context values available only after an authorization guard succeeds. *)
  module Secured : sig
    (** Protected request context. [dependency] remains the statically selected
        application value; principal and request ID are request-scoped. *)
    type 'a t = private
      { dependency : 'a
      ; principal : Petstore_principal.t
      ; request_id : string option
      }

    (** Returns the application dependency captured when the group was built. *)
    val dependency : 'a t -> 'a

    (** Returns the authenticated caller for this request. *)
    val principal : _ t -> Petstore_principal.t

    (** Returns the request correlation ID when access logging supplied one. *)
    val request_id : _ t -> string option
  end

  (** Accepts either a login/demo bearer or API key. *)
  val pet_lookup
    :  auth:Auth.t
    -> Sessions.database
    -> Sessions.database Secured.t Endpoint.Context.t

  (** Requires the official API key and injects [dependency]. *)
  val api_key
    :  auth:Auth.t
    -> Sessions.database
    -> Sessions.database Secured.t Endpoint.Context.t

  (** Requires a login session or the separate demo bearer. *)
  val session
    :  auth:Auth.t
    -> Sessions.database
    -> Sessions.database Secured.t Endpoint.Context.t

  (** Authenticates user-management requests. The application service checks
      ownership and administrative authority and may return HTTP 403. *)
  val management
    :  auth:Auth.t
    -> Sessions.database
    -> Sessions.database Secured.t Endpoint.Context.t

  (** Injects [dependency] without an authorization guard. *)
  val public : 'a -> 'a Endpoint.Context.t

  (** Stable JSON mapping and status-specific OpenAPI descriptions shared by
      controller groups. Descriptions do not change runtime error responses. *)
  val decode_errors : Endpoint.Decode_error_response.t
end
