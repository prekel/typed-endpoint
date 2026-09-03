(** Opium 0.18 backend for {!Typed_endpoint}.

    Compiled endpoint declarations produce ordinary Opium application
    transformations. Apply the resulting [app_builder] to an
    [Opium.Std.App.t]; framework middleware, connection lifecycle and server
    startup remain the application's responsibility. Route handlers run in
    [Lwt.t].

    Request bodies are consumed from Opium's stream at most once. The backend
    stops accumulating data as soon as the limit supplied by the endpoint is
    exceeded, so callers must not install middleware which consumes the same
    stream first unless that middleware replaces it. Header lookup follows
    Cohttp's case-insensitive HTTP semantics. *)
include
  Typed_endpoint.Backend.S
  with type req = Opium.Std.Request.t
   and type resp = Opium.Std.Response.t
   and type 'a io = 'a Lwt.t
   and type app_builder = Opium.Std.App.t -> Opium.Std.App.t
