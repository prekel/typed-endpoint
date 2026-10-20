open! Base

(** Request value for the Cohttp/Lwt backend. Path captures belong to the
    matched route, and the body is consumed by one dispatch. *)
type req

(** Native Cohttp response and body. Typed responses are buffered; the native
    pair allows application middleware to inspect and update HTTP metadata. *)
type resp = Cohttp.Response.t * Cohttp_lwt.Body.t

type 'a io = 'a Lwt.t

(** Immutable route collection. Routing is internal to this package and
    preserves the order supplied by typed-endpoint. *)
type app_builder

include
  Typed_endpoint.Backend.S
  with type req := req
   and type resp := resp
   and type 'a io := 'a io
   and type app_builder := app_builder

(** Raw request access for backend-specific contexts and guards. *)
module Request : sig
  (** Returns the original Cohttp request for this dispatch. *)
  val http : req -> Cohttp.Request.t

  (** Looks up a header using HTTP case-insensitive name comparison. *)
  val header : req -> string -> string option
end

(** Dispatches a native Cohttp request through the compiled routes. The body
    stays unconsumed until an endpoint reads it; decoding stops buffering as
    soon as its byte limit is exceeded. Middleware that consumes a body must
    supply a replacement before dispatching.

    Returns [404] for an unknown path and [405] with an [Allow] header when
    the path matches another method. Exceptions and Lwt cancellation propagate
    to the caller. Dispatch does not drain the remaining request body; the
    hosting Cohttp server owns connection reuse and body draining. *)
val dispatch
  :  app_builder
  -> request:Cohttp.Request.t
  -> body:Cohttp_lwt.Body.t
  -> resp io

(** Builds a callback suitable for [Cohttp_lwt_unix.Server.make] or another
    Cohttp/Lwt server. The connection argument is unused and remains abstract,
    so this package does not depend on Unix or a particular network transport.

    Application middleware can wrap the returned callback using native Cohttp
    request, body and response values. The caller owns server startup, TLS,
    timeouts and connection lifecycle. *)
val callback
  :  app_builder
  -> 'connection
  -> Cohttp.Request.t
  -> Cohttp_lwt.Body.t
  -> resp io
