open! Base
open Typed_endpoint

(** HTTP controller for inventory and order operations. Cross-aggregate
    validation stays in [Order_service]. *)
module Make
    (B : Backend.S)
    (Pets : Pet_service.S with type 'a io = 'a B.io)
    (_ : Order_service.S with type 'a io = 'a B.io and type database = Pets.database) : sig
  (** Endpoint instance owning the returned group types. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Builds separate inventory and order groups because only inventory uses
      the API-key guard. Both groups inject the same database resource. *)
  val groups : auth:Auth.t -> database:Pets.database -> Endpoint.Group.t list
end
