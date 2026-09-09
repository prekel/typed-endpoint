open! Base

(** Native direct-style backend for cohttp-eio 6.3.

    The route table and router are internal to this package. Typed-endpoint
    owns neither the Eio switch nor the network resources used by a server;
    their lifetime must enclose all calls made through {!server}. Application
    middleware can be supplied to {!server} or {!dispatch}; connection-level
    behavior belongs around the returned [Cohttp_eio.Server.t], outside the
    framework-agnostic core. *)
type req

type resp
type 'a io = 'a
type app_builder

(** A direct-style wrapper around one typed-endpoint dispatch. Middleware is
    entered in list order, so the first element is the outermost wrapper.
    It receives the raw Cohttp request but does not expose typed route internals.
    Passing a replaced request to [next] makes request-local header enrichment
    possible before route matching. *)
type middleware = request:Http.Request.t -> next:(Http.Request.t -> resp) -> resp

include
  Typed_endpoint.Backend.S
  with type req := req
   and type resp := resp
   and type 'a io := 'a io
   and type app_builder := app_builder

module Request : sig
  (** Returns the Cohttp request whose lifetime is that of the current handler.
      Do not retain it after the handler returns. *)
  val http : req -> Http.Request.t

  (** Looks up a header using HTTP case-insensitive name comparison. *)
  val header : req -> string -> string option
end

module Response : sig
  (** Returns the status selected by the typed handler. *)
  val status : resp -> Http.Status.t

  (** Returns the complete response headers passed to cohttp-eio. *)
  val headers : resp -> Http.Header.t

  (** Returns the buffered response body. Typed-endpoint responses are not
      streamed by this backend. *)
  val body : resp -> string

  (** Returns a response with [name] set to [value], replacing any existing
      values for that header. *)
  val with_header : resp -> name:string -> value:string -> resp
end

(** Dispatches one already-buffered request through the compiled route table.

    This entry point is intended for adapter-level tests and embeddings which
    already own the request body. It returns [405] when the decoded path exists
    for another method, including the available methods in [Allow], and [404]
    when no path matches. [body] is checked against the endpoint's byte limit
    before decoding. *)
val dispatch
  :  ?middlewares:middleware list
  -> app_builder
  -> request:Http.Request.t
  -> body:string
  -> resp

(** Builds a native cohttp-eio server callback from the compiled route table.

    Incoming bodies stay as cohttp-eio streams until an endpoint asks to decode
    one. The backend then reads through a bounded [Eio.Buf_read] operation
    and reports an oversized body without unbounded buffering. The caller is
    responsible for running the returned server with network resources whose
    lifetime remains valid. *)
val server : ?middlewares:middleware list -> app_builder -> Cohttp_eio.Server.t
