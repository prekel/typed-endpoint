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

(** Statically assembles the complete application and HTTP graph. Repository
    implementations are selected by functor application, while concrete
    runtime resources—such as an in-memory state or a Caqti pool—remain explicit
    arguments to {!compile}. The constraints prevent mixing effects from
    different backends. *)
module Make
    (B : Backend.S)
    (Pet_repository : Pet_repository.S with type 'a io = 'a B.io)
    (Order_repository : Order_repository.S with type 'a io = 'a B.io)
    (User_repository : User_repository.S with type 'a io = 'a B.io) : sig
  (** Endpoint instance used to compile the assembled controllers. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Pet service selected and built by this graph. *)
  module Pets : Pet_service.S with type 'a io = 'a B.io

  (** Order service wired statically to {!Pets}. *)
  module Orders : Order_service.S with type 'a io = 'a B.io

  (** User service selected and built by this graph. *)
  module Users : User_service.S with type 'a io = 'a B.io

  (** Creates service and controller instances from the supplied repository
      resources, collects their route groups, and adds runtime-only health,
      OpenAPI, and documentation UI endpoints. Every argument is named so the
      process-level dependency graph stays visible at the executable boundary. *)
  val compile
    :  auth:auth
    -> pet_repository:Pet_repository.t
    -> order_repository:Order_repository.t
    -> user_repository:User_repository.t
    -> Endpoint.Dsl.Compiled.t
end
