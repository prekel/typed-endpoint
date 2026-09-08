open! Base

(** Access-log event builder for the Petstore server entrypoints.

    Events are emitted as one flat JSON object per line. Request targets are
    reduced to their path before logging, so query parameters, bodies, and
    request headers are never included in the event. *)

type t
type request

(** Creates an access logger. The default writer appends JSONL to [stderr].
    Optional dependencies exist to make the wire format testable without a
    running HTTP framework. Writers must not raise: failures are ignored by the
    logger in any case. *)
val create
  :  ?now:(unit -> float)
  -> ?write:(string -> unit)
  -> ?fresh_id:(unit -> string)
  -> unit
  -> t

(** Begins an event for an incoming request. A supplied [request_id] is reused
    only when it contains 1 to 128 ASCII letters, digits, dots, underscores,
    or hyphens. Otherwise a server-generated ID is used. *)
val start : t -> method_:string -> target:string -> request_id:string option -> request

(** The correlation ID to return as [X-Request-Id]. *)
val request_id : request -> string

(** Emits a successful HTTP access event. [status] is the response status. *)
val finish : request -> status:int -> unit

(** Emits an error event for an exception that will be re-raised by the HTTP
    framework. The exception message is intended for trusted log sinks. *)
val fail : request -> exn -> unit
