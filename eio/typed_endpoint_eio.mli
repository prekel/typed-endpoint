open! Base

type req
type resp
type 'a io = 'a
type app_builder

include
  Typed_endpoint.Backend.S
  with type req := req
   and type resp := resp
   and type 'a io := 'a io
   and type app_builder := app_builder

module Request : sig
  val http : req -> Http.Request.t
  val header : req -> string -> string option
end

module Response : sig
  val status : resp -> Http.Status.t
  val headers : resp -> Http.Header.t
  val body : resp -> string
end

(** Dispatches one in-memory request through the compiled route table. *)
val dispatch : app_builder -> request:Http.Request.t -> body:string -> resp

(** Builds a native cohttp-eio server from compiled typed-endpoint routes. *)
val server : app_builder -> Cohttp_eio.Server.t
