open! Base
open Typed_endpoint

(** HTTP controller for user operations. *)
module Make (B : Backend.S) (Users : User_service.S with type 'a io = 'a B.io) : sig
  (** Endpoint instance owning the returned group types. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** User controller instance. *)
  type t

  (** Creates a controller with its complete service dependency set. *)
  val create : users:Users.t -> t

  (** Builds the public user route group with controller-scoped dependency
      injection. *)
  val groups : t -> Endpoint.Dsl.Group.t list
end
