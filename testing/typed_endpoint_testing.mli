open! Base

(** Deterministic in-memory backend for exercising compiled endpoints without
    starting an HTTP framework or server.

    The backend is direct-style and owns all request and response strings it
    creates. It intentionally models only the boundary required by
    {!Typed_endpoint.Backend.S}; framework middleware, streaming and connection
    behavior must be tested in the corresponding adapter. Header lookup is
    case-insensitive and request-body byte limits are enforced before payload
    decoding. *)
type request

type response
type app_builder

include
  Typed_endpoint.Backend.S
  with type req = request
   and type resp = response
   and type 'a io = 'a
   and type app_builder := app_builder

module Request : sig
  (** Creates a complete in-memory request. [target] may contain both a path and
      query string. Duplicate headers are preserved in insertion order; lookup
      returns the first matching name. *)
  val v
    :  ?headers:(string * string) list
    -> ?body:string
    -> meth:meth
    -> target:string
    -> unit
    -> request

  (** Returns the method supplied to {!v}. *)
  val meth : request -> meth

  (** Returns the target supplied to {!v}, before URI decomposition. *)
  val target : request -> string
end

module Response : sig
  (** Returns the numeric HTTP status code. *)
  val status : response -> int

  (** Returns response headers in emission order. Header names are not
      canonicalized. *)
  val headers : response -> (string * string) list

  (** Returns the complete buffered response body. *)
  val body : response -> string

  (** Parses {!body} as JSON. Failure contains Yojson's parse diagnostic and
      does not depend on the response [Content-Type]. *)
  val json : response -> (Yojson.Safe.t, string) Result.t
end

(** Dispatches one request synchronously through the compiled route table.

    Path segments are percent-decoded before matching. A matching path with the
    wrong method returns [405]; an unknown path returns [404]. The request value
    remains reusable, because dispatch derives route parameters in a fresh
    internal value and performs no observable mutation. *)
val dispatch : app_builder -> request -> response
