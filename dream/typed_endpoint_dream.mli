open! Base

(** Dream 1.0.0~alpha8 backend for {!Typed_endpoint}.

    An [app_builder] is an immutable collection of compiled routes. Convert it
    with {!router}, then compose the returned handler with Dream middleware in
    the application entrypoint. Typed-endpoint does not own Dream's server,
    connection lifecycle, or middleware stack. *)
type app_builder

include
  Typed_endpoint.Backend.S
  with type req = Dream.request
   and type resp = Dream.response
   and type 'a io = 'a Lwt.t
   and type app_builder := app_builder

(** Builds a Dream handler from compiled typed-endpoint routes.

    Routes sharing a path are grouped so Dream performs path matching once;
    dispatch then selects the declared HTTP method. A matched path with no
    matching method returns [405] with an [Allow] header. Requests unmatched by
    this router continue according to Dream router semantics.

    Handler request bodies are read directly from Dream's body stream and are
    therefore single-use. Reading stops once an endpoint's configured byte
    limit is exceeded. Middleware which inspects a body must preserve or
    replace the stream before this handler receives it. *)
val router : app_builder -> Dream.handler
