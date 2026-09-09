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
    (Database : Database.S with type 'a io = 'a B.io)
    (_ :
       Pet_repository.S
       with type 'a io = 'a B.io
        and type connection = Database.connection)
    (_ :
       Order_repository.S
       with type 'a io = 'a B.io
        and type connection = Database.connection)
    (_ :
       User_repository.S
       with type 'a io = 'a B.io
        and type connection = Database.connection) : sig
  (** Endpoint instance used to compile the assembled controllers. *)
  module Endpoint : module type of Typed_endpoint.Make (B)

  (** Pet service selected and built by this graph. *)
  module Pets : Pet_service.S with type 'a io = 'a B.io and type database = Database.t

  (** Order service wired statically to the pet and order repositories. *)
  module Orders : Order_service.S with type 'a io = 'a B.io and type database = Database.t

  (** User service selected and built by this graph. *)
  module Users : User_service.S with type 'a io = 'a B.io and type database = Database.t

  (** Collects stateless controller groups and adds runtime-only health,
      OpenAPI, and documentation UI endpoints. [database] is the sole runtime
      application resource; repository and service selection remains visible
      in the functor application. *)
  val compile
    :  ?interceptors:Endpoint.Dsl.Interceptor.t list
    -> auth:auth
    -> database:Database.t
    -> unit
    -> Endpoint.Dsl.Compiled.t
end
