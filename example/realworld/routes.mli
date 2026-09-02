open! Base

module type Request = sig
  type t

  val header : t -> string -> string option
end

module Make (B : Typed_endpoint.Backend.S) (Request : Request with type t = B.req) : sig
  module Endpoint : module type of Typed_endpoint.Make (B)

  val compile : Article_service.t -> Endpoint.D.Compiled.t
end
