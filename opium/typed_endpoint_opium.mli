(** Opium 0.17.1 and 0.18 backend for {!Typed_endpoint}.

    Compiled endpoint declarations produce an immutable route collection.
    Attach it once with {!mount}; framework middleware, connection lifecycle
    and server startup remain the application's responsibility. Route handlers
    run in [Lwt.t].

    Request bodies are consumed from Opium's stream at most once. The backend
    stops accumulating data as soon as the limit supplied by the endpoint is
    exceeded, so callers must not install middleware which consumes the same
    stream first unless that middleware replaces it. Header lookup follows
    Cohttp's case-insensitive HTTP semantics. *)
type app_builder

include
  Typed_endpoint.Backend.S
  with type req = Opium.Std.Request.t
   and type resp = Opium.Std.Response.t
   and type 'a io = 'a Lwt.t
   and type app_builder := app_builder

(** Registers every typed route and one shared 405/Allow middleware. Repeated
    calls are supported for incremental migration, but one mount per compiled
    route collection avoids a middleware chain proportional to route count. *)
val mount : app_builder -> Opium.Std.App.t -> Opium.Std.App.t
