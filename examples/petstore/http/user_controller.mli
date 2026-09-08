open! Base
open Typed_endpoint

(** HTTP controller for user operations. *)
module Make (B : Backend.S) (Users : User_service.S with type 'a io = 'a B.io) : sig
  (** Endpoint instance owning the returned group types. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Builds the public user route group and injects the runtime database
      resource into its handlers. *)
  val groups : database:Users.database -> Endpoint.Dsl.Group.t list
end
