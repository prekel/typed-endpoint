(** User-management and login HTTP routes. The controller maps authentication
    results and domain authorization failures to declared HTTP responses;
    application services manage sessions and transactions. *)

open! Base
open Typed_endpoint

(** HTTP controller for user operations. *)
module Make
    (B : Backend.S)
    (Users : User_service.S with type 'a io = 'a B.io)
    (_ : Session_service.S with type 'a io = 'a B.io and type database = Users.database) : sig
  (** Endpoint instance owning the returned group types. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Builds public account/login routes and a protected logout group.
      Passwords are accepted only in request DTOs and never returned. *)
  val groups : auth:Auth.t -> database:Users.database -> Endpoint.Group.t list
end
