open! Base
open Typed_endpoint

(** HTTP controller for inventory and order operations. Its constructor makes
    both service dependencies visible; cross-aggregate validation itself stays
    in [Order_service]. *)
module Make
    (B : Backend.S)
    (Pets : Pet_service.S with type 'a io = 'a B.io)
    (Orders : Order_service.S with type 'a io = 'a B.io) : sig
  (** Endpoint instance owning the returned group types. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Store controller instance. *)
  type t

  (** Creates a controller with its complete service dependency set. *)
  val create : pets:Pets.t -> orders:Orders.t -> t

  (** Builds separate inventory and order groups because only inventory uses
      the API-key guard. *)
  val groups : auth:Auth.t -> t -> Endpoint.Dsl.Group.t list
end
