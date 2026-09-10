open! Base
open Typed_endpoint

(** HTTP controller for pet operations. It owns route declarations and DTO
    mapping, while the stateless service owns domain behavior and transaction
    boundaries. *)
module Make (B : Backend.S) (Pets : Pet_service.S with type 'a io = 'a B.io) : sig
  (** Endpoint instance owning the returned group types. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Builds route groups with group-scoped authorization and database
      injection. One controller produces two groups because the official pet
      operations use two distinct security policies. *)
  val groups : auth:Auth.t -> database:Pets.database -> Endpoint.Group.t list
end
