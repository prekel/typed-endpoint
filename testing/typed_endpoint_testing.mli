open! Base

(** Immutable request captured by the deterministic in-memory backend. It owns
    its request and response strings and models only the boundary required by
    {!Typed_endpoint.Backend.S}; framework middleware, streaming, and connection
    behavior belong in adapter tests. Header lookup is case-insensitive and
    request-body byte limits are enforced before payload decoding. *)
type request

(** Fully buffered response captured by the in-memory backend. *)
type response

(** In-memory route collection produced by endpoint compilation. *)
type app_builder

(** Backend capabilities specialized to the in-memory request and response
    values. *)
include
  Typed_endpoint.Backend.S
  with type req = request
   and type resp = response
   and type 'a io = 'a
   and type app_builder := app_builder

(** Request construction and inspection helpers. *)
module Request : sig
  (** Creates a complete in-memory request. [target] may contain both a path and
      query string. Duplicate headers are preserved in insertion order; lookup
      returns the first matching name. *)
  val v
    :  ?headers:(string * string) list
    -> ?body:string
    -> meth:Typed_endpoint.Method.t
    -> target:string
    -> unit
    -> request

  (** Returns the method supplied to {!v}. *)
  val meth : request -> Typed_endpoint.Method.t

  (** Returns the target supplied to {!v}, before URI decomposition. *)
  val target : request -> string
end

(** Response inspection helpers. *)
module Response : sig
  (** Returns the numeric HTTP status code. *)
  val status : response -> int

  (** Returns response headers in emission order. Header names are not
      canonicalized. *)
  val headers : response -> (string * string) list

  (** Looks up the first response header with a case-insensitive name. *)
  val header : response -> string -> string option

  (** Returns the complete buffered response body. *)
  val body : response -> string

  (** Parses {!body} as JSON. Failure contains Yojson's parse diagnostic and
      does not depend on the response [Content-Type]. *)
  val json : response -> (Yojson.Safe.t, string) Result.t
end

(** Dispatches one request synchronously through the compiled route table.

    Path segments are percent-decoded before matching. A matching path with the
    wrong method returns [405] and lists available methods in [Allow]; an
    unknown path returns [404]. The request value remains reusable, because
    dispatch derives route parameters in a fresh internal value and performs no
    observable mutation. *)
val dispatch : app_builder -> request -> response

(** Concise request construction and dispatch for application tests. *)
module Client : sig
  (** Creates an immutable request and immediately dispatches it through
      [routes]. [target] may include a query string. *)
  val call
    :  app_builder
    -> ?headers:(string * string) list
    -> ?body:string
    -> Typed_endpoint.Method.t
    -> string
    -> response
end

(** Reusable black-box laws for every {!Typed_endpoint.Backend.S}. Adapter
    tests provide only request/response conversion and effect execution. *)
module Backend_conformance : sig
  (** Adapter-specific operations needed to execute shared backend laws. *)
  module type Harness = sig
    (** Backend under test. *)
    module Backend : Typed_endpoint.Backend.S

    (** Compiles and dispatches a request using the backend under test. *)
    val call
      :  Backend.app_builder
      -> ?headers:(string * string) list
      -> ?body:string
      -> Typed_endpoint.Method.t
      -> string
      -> Backend.resp Backend.io

    (** Extracts the numeric response status. *)
    val status : Backend.resp -> int

    (** Looks up a response header case-insensitively. *)
    val header : Backend.resp -> string -> string option

    (** Reads the response body in the backend's effect. *)
    val body : Backend.resp -> string Backend.io
  end

  (** Test suite generated for one adapter harness. *)
  module Make (H : Harness) : sig
    (** Runs bounded-body, representation, routing, decode-error, typed-header,
        duplicate-query, and declaration-order checks. *)
    val run : unit -> unit H.Backend.io
  end
end
