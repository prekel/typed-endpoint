open! Base

type app_builder

include
  Typed_endpoint.Backend.S
  with type req = Dream.request
   and type resp = Dream.response
   and type 'a io = 'a Lwt.t
   and type app_builder := app_builder

(** Builds a Dream handler from compiled typed-endpoint routes. *)
val router : app_builder -> Dream.handler
