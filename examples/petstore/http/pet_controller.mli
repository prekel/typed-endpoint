open! Base
open Typed_endpoint

(** HTTP controller for pet operations. It owns route declarations and DTO
    mapping, while the injected service owns domain behavior. *)
module Make (B : Backend.S) (Pets : Pet_service.S with type 'a io = 'a B.io) : sig
  (** Endpoint instance owning the returned group types. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Pet controller instance. *)
  type t

  (** Creates a controller with its complete dependency set. *)
  val create : pets:Pets.t -> t

  (** Builds route groups with group-scoped authorization and controller
      injection. One controller produces two groups because the official pet
      operations use two distinct security policies. *)
  val groups : auth:Auth.t -> t -> Endpoint.Dsl.Group.t list
end
