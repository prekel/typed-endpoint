open! Base
open Typed_endpoint

(** Credentials accepted by the example authorization guards. *)
type auth = Auth.t =
  { bearer_token : string
  ; api_key : string
  }

(** Reads demo credentials from [PETSTORE_BEARER_TOKEN] and
    [PETSTORE_API_KEY], falling back to local-development values. *)
val auth_from_env : unit -> auth

(** OpenAPI document metadata used by every server entrypoint. *)
val openapi_config : Openapi.Config.t

(** Advanced composition entrypoint. Applications provide service modules and
    values built from arbitrary repository adapters—for example Lwt services
    backed by PGOCaml. The functor constraints ensure every dependency uses the
    selected HTTP backend's effect. *)
module Make_with_services
    (B : Backend.S)
    (Pets : Pet_service.S with type 'a io = 'a B.io)
    (Orders : Order_service.S with type 'a io = 'a B.io)
    (Users : User_service.S with type 'a io = 'a B.io) : sig
  (** Endpoint instance used to compile the assembled controllers. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Values expected from the application's runtime composition root. *)
  type services = (Pets.t, Orders.t, Users.t) Services.t

  (** Constructs controllers from the supplied services, collects their route
      groups, and adds runtime-only health, OpenAPI, and Swagger UI endpoints. *)
  val compile : auth:auth -> services -> Endpoint.Dsl.Compiled.t
end

(** Development entrypoint with an in-memory composition root. The nested
    [Services] module is the only place that chooses concrete repositories. *)
module Make (B : Backend.S) : sig
  module Services : sig
    (** In-memory pet service selected by the default composition root. *)
    module Pets : Pet_service.S with type 'a io = 'a B.io

    (** In-memory order service selected by the default composition root. *)
    module Orders : Order_service.S with type 'a io = 'a B.io

    (** In-memory user service selected by the default composition root. *)
    module Users : User_service.S with type 'a io = 'a B.io

    (** Complete application-scoped graph. *)
    type t = (Pets.t, Orders.t, Users.t) Services.t

    (** Creates an isolated application-scoped service graph. *)
    val create : unit -> t
  end

  (** Endpoint instance used by the default application. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Compiles the default in-memory controllers and runtime routes. *)
  val compile : auth:auth -> Services.t -> Endpoint.Dsl.Compiled.t
end
