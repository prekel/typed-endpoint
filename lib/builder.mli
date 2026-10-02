open! Base

(** Typed JSON Schema constructors shared by endpoint metadata and OpenAPI. *)
module Json_schema : module type of Json_schema

(** OpenAPI schema, tag, and human-readable description metadata. *)
module Metadata : sig
  (** Metadata keeps a schema tied to the OCaml wire type. [schema_name], when
      present, registers the schema in OpenAPI [components/schemas] and renders
      references to it. Reusing a name for a different schema is a compile error. *)
  type 'a t

  (** Creates metadata for exactly ['a]. [schema_name] opts into a reusable
      OpenAPI component; names are validated during compilation. *)
  val v
    :  schema:'a Json_schema.t
    -> ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> 'a t
end

(** OpenAPI security schemes and requirements. A list of requirements denotes
    alternatives (OR); use {!Security.all} inside one requirement for AND. *)
module Security : sig
  (** A reusable security scheme registered in [components/securitySchemes]. *)
  module Scheme : sig
    (** The request location of an API key. *)
    type api_key_location =
      [ `Header
      | `Query
      | `Cookie
      ]

    (** Supported OpenAPI security scheme kinds. OAuth 2 implicit scopes pair a
        machine-readable scope name with its human-readable description. *)
    type kind =
      | Api_key of
          { parameter : string
          ; location : api_key_location
          }
      | Http_bearer of { bearer_format : string option }
      | Oauth2_implicit of
          { authorization_url : string
          ; scopes : (string * string) list
          }

    (** Scheme [name] is its OpenAPI component key. Definitions that reuse a
        name must be structurally identical or compilation fails. *)
    type t = private
      { name : string
      ; description : string
      ; kind : kind
      }

    (** Declares an API key read from [parameter] at [location]. *)
    val api_key
      :  name:string
      -> parameter:string
      -> location:api_key_location
      -> description:string
      -> unit
      -> t

    (** Declares an HTTP Bearer authentication scheme. [bearer_format] is only
        a documentation hint and does not enforce a token representation. *)
    val http_bearer
      :  name:string
      -> ?bearer_format:string
      -> description:string
      -> unit
      -> t

    (** Declares the implicit OAuth 2 flow and the complete set of scopes that
        operation requirements may reference. *)
    val oauth2_implicit
      :  name:string
      -> authorization_url:string
      -> scopes:(string * string) list
      -> description:string
      -> unit
      -> t
  end

  (** Schemes in one requirement must all be satisfied (AND). Scope lists are
      valid only for OAuth 2 schemes and are validated during compilation. *)
  type requirement = (Scheme.t * string list) list

  (** Creates a one-scheme requirement. [scopes] defaults to the empty list. *)
  val require : ?scopes:string list -> Scheme.t -> requirement

  (** Conjoins requirements, merging repeated identical schemes and
      deduplicating their scopes. *)
  val all : requirement list -> requirement
end

(** An authenticated identity together with the scopes granted for the current
    request. The identity type belongs to the application; the HTTP core only
    carries it and never performs runtime type lookup. *)
module Principal : sig
  (** Opaque identity paired with request-scoped authorization scopes. *)
  type 'identity t

  (** Creates a principal with a deterministic, duplicate-free scope list. *)
  val v : ?scopes:string list -> identity:'identity -> unit -> 'identity t

  (** Extracts the application-defined identity. *)
  val identity : 'identity t -> 'identity

  (** Returns scopes in their stored order without duplicates. *)
  val scopes : _ t -> string list

  (** Tests whether the principal carries [scope]. *)
  val has_scope : _ t -> string -> bool
end

(** Stable, low-cardinality metadata for one matched runtime route.
    [path_template] uses OpenAPI-style captures such as [/pet/{petId}], never
    the raw request target. *)
module Route_info : sig
  (** Stable route metadata passed to runtime interceptors. *)
  type t = private
    { operation_id : string option
    ; method_ : string
    ; path_template : string
    ; tags : string list
    ; security : Security.requirement list
    }
end

(** OpenAPI document configuration shared by all backends. *)
module Openapi : sig
  (** A server on which the described API is available. *)
  module Server : sig
    (** [url] is emitted verbatim and may contain OpenAPI server variables. *)
    type t =
      { url : string
      ; description : string option
      }

    (** Creates a server entry with an optional human-readable description. *)
    val v : url:string -> ?description:string -> unit -> t
  end

  (** Top-level OpenAPI [info] and server configuration. *)
  module Config : sig
    (** [title] and [version] are required OpenAPI info fields. [version]
        describes the application API, not the OpenAPI specification version. *)
    type t =
      { title : string
      ; version : string
      ; description : string option
      ; servers : Server.t list
      }

    (** Creates document configuration. [servers] defaults to the empty list. *)
    val v
      :  title:string
      -> version:string
      -> ?description:string
      -> ?servers:Server.t list
      -> unit
      -> t
  end
end

(** A wire type carrying the schema and documentation used by OpenAPI. Keeping
    the metadata typed prevents accidentally passing metadata for another DTO. *)
module type Metadatable = sig
  (** OCaml value represented by the accompanying metadata. *)
  type t

  (** The runtime JSON shape and documentation for [t]. *)
  val metadata : t Metadata.t
end

(** HTTP methods accepted by typed and runtime-only routes. [`Other] preserves
    extension methods without coupling the core to a backend library. *)
module Method : sig
  (** Supported methods, including extension methods. *)
  type t =
    [ `GET
    | `POST
    | `HEAD
    | `DELETE
    | `PATCH
    | `PUT
    | `OPTIONS
    | `TRACE
    | `CONNECT
    | `Other of string
    ]
end

(** Backend-independent HTTP response statuses. *)
module Status : sig
  (** Statuses suitable for authentication, authorization, and other guards. *)
  type client_error =
    [ `Bad_request
    | `Unauthorized
    | `Payment_required
    | `Forbidden
    | `Not_found
    | `Method_not_allowed
    | `Not_acceptable
    | `Proxy_authentication_required
    | `Request_timeout
    | `Conflict
    | `Gone
    | `Length_required
    | `Precondition_failed
    | `Request_entity_too_large
    | `Request_uri_too_long
    | `Unsupported_media_type
    | `Requested_range_not_satisfiable
    | `Expectation_failed
    | `I_m_a_teapot
    | `Enhance_your_calm
    | `Unprocessable_entity
    | `Locked
    | `Failed_dependency
    | `Upgrade_required
    | `Precondition_required
    | `Too_many_requests
    | `Request_header_fields_too_large
    | `No_response
    | `Retry_with
    | `Blocked_by_windows_parental_controls
    | `Wrong_exchange_server
    | `Client_closed_request
    ]

  (** Every named status supported by the library, plus arbitrary numeric
      extension statuses. Compilation rejects response declarations outside
      the HTTP range 100 through 599. *)
  type t =
    [ `Code of int
    | `Continue
    | `Switching_protocols
    | `Processing
    | `Checkpoint
    | `OK
    | `Created
    | `Accepted
    | `Non_authoritative_information
    | `No_content
    | `Reset_content
    | `Partial_content
    | `Multi_status
    | `Already_reported
    | `Im_used
    | `Multiple_choices
    | `Moved_permanently
    | `Found
    | `See_other
    | `Not_modified
    | `Use_proxy
    | `Switch_proxy
    | `Temporary_redirect
    | `Permanent_redirect
    | client_error
    | `Internal_server_error
    | `Not_implemented
    | `Bad_gateway
    | `Service_unavailable
    | `Gateway_timeout
    | `Http_version_not_supported
    | `Variant_also_negotiates
    | `Insufficient_storage
    | `Loop_detected
    | `Bandwidth_limit_exceeded
    | `Not_extended
    | `Network_authentication_required
    | `Network_read_timeout_error
    | `Network_connect_timeout_error
    ]

  (** Converts a supported status token to its numeric HTTP code. *)
  val code : [< t ] -> int
end

(** Capabilities every concrete HTTP server adapter must provide. *)
module Backend : sig
  (** Minimal capability contract implemented by each HTTP adapter. Application
      code normally consumes an existing backend rather than implementing this
      signature directly. *)
  module type S = sig
    (** Native request and response values owned by the HTTP framework. *)
    type req

    (** Native response value returned by the backend. *)
    type resp

    (** Backend effect. Lwt adapters use [type 'a io = 'a Lwt.t]; direct-style
        Eio uses the identity type. *)
    type 'a io

    (** Lawful sequencing operations for [io]. Besides [return], [bind], and
        [map], this exposes [Let_syntax] for backend-independent [let%bind] and
        [let%map]. Derived collection combinators execute sequentially. *)
    module Io : Base.Monad.S with type 'a t = 'a io

    (** A backend router value accumulated by {!combine}. *)
    type app_builder

    (** Registers one already-rendered backend path and handler. *)
    val route : Method.t -> string -> (req -> resp io) -> app_builder

    (** Retrieves a router-decoded path capture. *)
    val param : req -> string -> string

    (** Retrieves all values for one query name in wire order. Scalar DSL
        parameters reject more than one value instead of inheriting a
        framework-specific first/last-value policy. *)
    val query : req -> string -> string list

    (** Header lookup is case-insensitive in HTTP backends. *)
    val header : req -> string -> string option

    (** Reads at most [max_bytes]. Backends must stop buffering once the limit
        is exceeded and return [`Too_large]. *)
    val body_to_string : max_bytes:int -> req -> (string, [ `Too_large ]) Result.t io

    (** Creates one buffered response. The caller supplies the complete header
        list, including [Content-Type] when the body has a representation. An
        omitted status means HTTP 200. Duplicate header names are preserved. *)
    val respond
      :  ?status:Status.t
      -> headers:(string * string) list
      -> body:string
      -> unit
      -> resp io

    (** Convenience constructors with fixed representation semantics. Empty
        responses have no [Content-Type]; string, HTML, and JSON responses use
        their canonical media types. *)
    val respond_empty : ?status:Status.t -> unit -> resp io

    (** Emits a UTF-8 plain-text response. *)
    val respond_string : ?status:Status.t -> string -> resp io

    (** Emits an HTML response using the backend's canonical HTML media type. *)
    val respond_html : ?status:Status.t -> string -> resp io

    (** Emits a JSON response using the backend's canonical JSON media type. *)
    val respond_json : ?status:Status.t -> Yojson.Safe.t -> resp io

    (** Combines routers while preserving declaration order. Runtime assembly
        places static paths before otherwise overlapping capture paths. *)
    val combine : app_builder -> app_builder -> app_builder

    (** The identity router containing no routes. *)
    val empty : app_builder
  end
end

(** A response returned by a handler violates its declared status contract. *)
module Runtime_error : sig
  (** Runtime response-contract or response-header failure. *)
  type t =
    | Undeclared_response_case of
        { meth : string
        ; path : string
        ; status : int
        ; declared : int list
        }
    | Invalid_response_header of
        { name : string
        ; reason : string
        }

  (** Produces a stable diagnostic without including a rejected header value. *)
  val to_string : t -> string
end

(** Raised when a handler returns a case token absent from its response declaration. *)
exception Runtime_error of Runtime_error.t

(** Codecs shared by path and query parameters. A codec is the single source
    for runtime parsing and the parameter's OpenAPI schema. *)
module Parameter : sig
  (** Scalar query and path codec signature. *)
  module type S = sig
    (** OCaml value parsed from one request parameter. *)
    type t

    (** Parses one percent-decoded path or query value. [Error message] becomes
        part of the configured decode-error response. *)
    val of_string : string -> (t, string) Result.t

    (** Schema and description used to document the decoded value. *)
    include Metadatable with type t := t
  end

  (** Builds a first-class codec without requiring a named module. *)
  val v
    :  schema:'a Json_schema.t
    -> ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> of_string:(string -> ('a, string) Result.t)
    -> unit
    -> (module S with type t = 'a)

  (** Built-in codecs with matching primitive JSON schemas. Boolean values are
      deliberately restricted to lowercase [true] and [false]. *)
  val string
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = string)

  (** Parses a decimal OCaml integer and documents an integer schema. *)
  val int
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = int)

  (** Parses a decimal 64-bit integer and documents an int64 schema. *)
  val int64
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = int64)

  (** Parses a finite floating-point value and documents a number schema. *)
  val float
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = float)

  (** Parses only lowercase true and false. *)
  val bool
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = bool)
end

(** Bidirectional codecs and declarations for scalar HTTP headers. Header names
    are validated during compilation; values emitted by responses are rejected
    at runtime if they contain CR or LF. *)
module Header : sig
  (** Codec for one header value and the schema exposed in OpenAPI. *)
  module type S = sig
    (** OCaml value represented by one header field. *)
    type t

    (** Parses one incoming header value. *)
    val of_string : string -> (t, string) Result.t

    (** Formats a typed value for a response header. *)
    val to_string : t -> string

    (** Associates the header value type with its schema and documentation. *)
    include Metadatable with type t := t
  end

  (** Creates a first-class bidirectional codec for a header value. *)
  val v
    :  schema:'a Json_schema.t
    -> ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> of_string:(string -> ('a, string) Result.t)
    -> to_string:('a -> string)
    -> unit
    -> (module S with type t = 'a)

  (** Creates a string header codec. *)
  val string
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = string)

  (** Creates an integer header codec. *)
  val int
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = int)

  (** Creates an int64 header codec. *)
  val int64
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = int64)

  (** Creates a boolean header codec. *)
  val bool
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = bool)

  (** Typed declaration of a named header and its codec. *)
  type 'a t

  (** Creates a required header declaration, which contributes ['a] to the
      handler argument list when used as a request header. *)
  val required : string -> (module S with type t = 'a) -> 'a t

  (** An optional header contributes ['a option] to the handler argument list
      and is omitted from a response when its value is [None]. *)
  val optional : string -> (module S with type t = 'a) -> 'a option t
end

(** JSON request-payload codec signature consumed by {!Make.Request.json}. *)
module Request_payload : sig
  (** Codec signature implemented by JSON request DTOs. Its decoder runs only
      after media type, body-size, and JSON syntax checks have succeeded. *)
  module type S = sig
    (** OCaml representation decoded from the JSON body. *)
    type t

    (** Documents the payload schema and metadata. *)
    include Metadatable with type t := t

    (** Decodes one already-parsed JSON value into the request DTO. *)
    val of_yojson : Yojson.Safe.t -> (t, string) Result.t
  end
end

(** JSON response-payload codec signature consumed by {!Make.Response.json}. *)
module Response_payload : sig
  (** Codec signature implemented by JSON response DTOs. The declared schema
      must describe the value emitted by [to_yojson]. *)
  module type S = sig
    (** OCaml representation encoded in the JSON body. *)
    type t

    (** Documents the payload schema and metadata. *)
    include Metadatable with type t := t

    (** Encodes the response DTO as its declared JSON wire shape. *)
    val to_yojson : t -> Yojson.Safe.t
  end
end

(** Convenience signature for DTOs used in both request and response bodies. *)
module Json_payload : sig
  (** Codec signature implemented by DTOs used in both request and response
      bodies. *)
  module type S = sig
    (** OCaml representation used for both request and response bodies. *)
    type t

    (** Documents the payload schema and metadata. *)
    include Metadatable with type t := t

    (** Decodes one JSON value into the DTO. *)
    val of_yojson : Yojson.Safe.t -> (t, string) Result.t

    (** Encodes the DTO using the same wire shape documented by metadata. *)
    val to_yojson : t -> Yojson.Safe.t
  end
end

(** Failures reported before an endpoint handler is invoked. *)
module Decode_error : sig
  (** Failures produced before the user handler runs. They map to 400, 413, or
      415 according to the constructor; applications control only the JSON
      payload through {!Make.Decode_error_response}. *)
  type t =
    | Invalid_parameter of
        { source : [ `Path | `Query | `Header ]
        ; name : string
        ; value : string
        ; error : string
        }
    | Missing_parameter of
        { source : [ `Path | `Query | `Header ]
        ; name : string
        }
    | Duplicate_parameter of
        { source : [ `Query ]
        ; name : string
        }
    | Invalid_json of { error : string }
    | Invalid_body of { error : string }
    | Unsupported_media_type of
        { expected : string list
        ; actual : string option
        }
    | Body_too_large of { max_bytes : int }
end

(** Specializes the endpoint DSL to a backend while preserving its native
    effect and application-builder types. *)
module Make (B : Backend.S) : sig
  (** Backend effect operations re-exported for handlers and injected
        services. Open [Io.Let_syntax] to use [ppx_let]. *)
  module Io : Base.Monad.S with type 'a t = 'a B.io

  (** Request-body declarations and runtime decoding. *)
  module Request : sig
    (** Runtime request decoding paired with its OpenAPI request-body
            contract. *)
    type _ t

    (** A request without a body. The handler receives [()]. *)
    val empty : unit t

    (** Requires a JSON media type, reads no more than [max_body_bytes], and
            then invokes the DTO decoder. *)
    val json : ?max_body_bytes:int -> (module Request_payload.S with type t = 'a) -> 'a t

    (** A UTF-8 text body requiring [Content-Type: text/plain]. *)
    val text : ?max_body_bytes:int -> description:string -> unit -> string t

    (** An opaque byte string requiring
            [Content-Type: application/octet-stream]. The backend enforces
            [max_body_bytes] before returning the body. *)
    val binary : ?max_body_bytes:int -> description:string -> unit -> string t
  end

  (** Response-body declarations and typed response cases. *)
  module Response : sig
    (** Runtime response encoding paired with its OpenAPI content contract. *)
    type 'a t

    (** A typed response capability passed positionally to the handler. Its
            first parameter carries the declared status variant and its second
            parameter carries the payload type. *)
    type (+'status, 'payload) case constraint 'status = [< Status.t ]

    (** Declares the exact JSON wire type returned by the handler. *)
    val json : (module Response_payload.S with type t = 'a) -> 'a t

    (** Declares a [text/plain] response. *)
    val text : description:string -> unit -> string t

    (** Declares a body-less response, for example a [`No_content] case. *)
    val empty : description:string -> unit -> unit t

    (** Adds one required or optional typed header. The resulting response
            value is [(header, body)]; multiple calls nest pairs from the
            outside in and preserve declaration order on the wire. *)
    val with_header : 'header Header.t -> 'body t -> ('header * 'body) t
  end

  (** A response declaration chain. ['handler] is the handler before its
          positional response capabilities are supplied; ['terminal] is the
          remaining handler after all capabilities have been supplied. *)
  type ('handler, 'terminal) responses

  (** Associates one HTTP status with its payload codec and adds its typed
          capability as the next positional handler argument. *)
  val case
    :  ([< Status.t ] as 'status)
    -> 'a Response.t
    -> (('status, 'a) Response.case -> 'terminal, 'terminal) responses

  (** Existential handler result retaining the exact case/payload pairing. *)
  type reply

  (** Combines declarations from left to right. The handler receives their
          capabilities in the same order. *)
  val ( <|> )
    :  ('handler, 'middle) responses
    -> ('middle, 'terminal) responses
    -> ('handler, 'terminal) responses

  (** Returns a response through [case]. Case membership is verified before
          rendering; the backend effect is returned directly for ergonomic
          handler branches. *)
  val respond : ('status, 'a) Response.case -> 'a -> reply B.io

  (** Typed values and guards resolved before request decoding. *)
  module Context : sig
    (** A typed computation performed once before parameter and body
            decoding. Contexts form an applicative: their complete structure is
            known before a request is handled, so runtime resolution and the
            corresponding OpenAPI responses and security requirements stay in
            sync.

            Binary combinators resolve from left to right and stop at the first
            rejection. Declared responses from every operand are retained, and
            their security alternatives are combined as logical AND. *)
    type 'a t

    (** Standard applicative operations. In particular, [return] injects an
            application value, [all] collects a homogeneous list of contexts,
            and [all_unit] sequences independent guards. This interface does not
            provide [bind], because request-dependent context structure could
            not be described completely in OpenAPI. *)
    include Base.Applicative.S with type 'a t := 'a t

    (** Syntax support for [let%map] and simultaneous [and] bindings from
            [ppx_let]. Bindings retain left-to-right resolution order. *)
    module Let_syntax : sig
      (** Operators recognized by the outer let-map syntax. *)
      val return : 'a -> 'a t

      val ( >>| ) : 'a t -> ('a -> 'b) -> 'b t
      val ( <*> ) : ('a -> 'b) t -> 'a t -> 'b t
      val ( *> ) : unit t -> 'a t -> 'a t
      val ( <* ) : 'a t -> unit t -> 'a t

      (** Nested syntax required by ppx_let for applicative contexts. *)
      module Let_syntax : sig
        (** Returns a context containing one value. *)
        val return : 'a -> 'a t

        (** Maps over the value produced by a context. *)
        val map : 'a t -> f:('a -> 'b) -> 'b t

        (** Resolves both contexts from left to right. *)
        val both : 'a t -> 'b t -> ('a * 'b) t

        (** Marker module used by ppx_let to open the right-hand side. *)
        module Open_on_rhs : sig end
      end
    end

    (** The raw backend request. Pass it to {!handle_with} explicitly
            when framework-neutral dependencies are insufficient. *)
    val request : B.req t
  end

  (** Constructors for application-wide and request-scoped dependencies. *)
  module Dependency : sig
    (** Injects an immutable application dependency into every request. *)
    val value : 'a -> 'a Context.t

    (** Resolves a request-scoped dependency before request decoding. *)
    val of_request : (B.req -> 'a B.io) -> 'a Context.t
  end

  (** Authentication and authorization checks represented in the route contract. *)
  module Guard : sig
    (** Builds a guard whose successful typed context is passed to the handler.
            Rejections are rendered with [response] and included in OpenAPI.
            Entries in [security] are OpenAPI alternatives (OR). Compose guards
            with {!Context.both} to require all of them (AND). *)
    val v
      :  ?security:Security.requirement list
      -> status:Status.client_error
      -> response:'error Response.t
      -> check:(B.req -> ('context, 'error) Result.t B.io)
      -> unit
      -> 'context Context.t

    (** Authentication-specific name for {!v}. A successful check returns
            a typed principal which can be combined with request-scoped
            dependencies through {!Context}. *)
    val authenticate
      :  ?security:Security.requirement list
      -> status:Status.client_error
      -> response:'error Response.t
      -> check:(B.req -> ('identity Principal.t, 'error) Result.t B.io)
      -> unit
      -> 'identity Principal.t Context.t
  end

  (** Policies for rendering failures produced during automatic request decoding. *)
  module Decode_error_response : sig
    (** A typed rendering policy for failures that occur before the handler. *)
    type t

    (** Safe built-in policy used when no endpoint, group, or compile-level
            override is supplied. It returns a JSON object with a stable [code]
            category and sanitized [message], omits decoder diagnostics and
            rejected raw values, and uses the [TypedEndpointDecodeError]
            component schema. *)
    val default : t

    (** Defines one typed JSON shape for path, query, media-type, size, and
            body decode failures. Runtime selects the fixed 400, 413, or 415
            status and OpenAPI declares every status reachable by the endpoint. *)
    val json
      :  payload:(module Response_payload.S with type t = 'a)
      -> map:(Decode_error.t -> 'a)
      -> t
  end

  (** An existential route whose handler types remain checked at creation. *)
  type route

  (** A route-aware runtime wrapper. It runs only after a route has
          matched. The first interceptor in a compile list is the outermost
          wrapper. *)
  type interceptor =
    route_info:Route_info.t -> request:B.req -> next:(unit -> B.resp B.io) -> B.resp B.io

  (** A collection of routes sharing metadata and an optional context. *)
  module Group : sig
    (** Abstract route-group value consumed by {!compile}. *)
    type t

    (** Creates a group of routes with shared metadata. [decode_error]
            overrides the application policy for fallible routes unless an
            endpoint supplies its own policy. *)
    val make
      :  ?prefix:string list
      -> ?decode_error:Decode_error_response.t
      -> ?summary:string
      -> ?tags:string list
      -> ?deprecated:bool
      -> description:string
      -> route list
      -> t

    (** An endpoint declaration waiting for a group-owned context. The type
            parameter prevents attaching a context of another type. *)
    type 'context route

    (** Attaches one typed context to every route finalized with [==>]. The
            context is resolved only for the
            matched route, and its guard responses and security requirements
            are emitted on every attached OpenAPI operation. Split routes into
            multiple groups when they need different authorization policies. *)
    val make_with_context
      :  ?prefix:string list
      -> ?decode_error:Decode_error_response.t
      -> ?summary:string
      -> ?tags:string list
      -> ?deprecated:bool
      -> description:string
      -> context:'context Context.t
      -> 'context route list
      -> t
  end

  (** A named typed path or query argument. The URI-first DSL's abstract
          phase types enforce the declaration order path -> query -> headers ->
          documentation -> request -> responses -> handler. The operator
          determines an argument's location and whether it is optional. *)
  type 'a argument

  (** Associates a path or query name with a typed scalar codec. *)
  val arg : string -> (module Parameter.S with type t = 'a) -> 'a argument

  (** URI under construction, indexed by its legal declaration phase. *)
  type ('phase, 'handler, 'terminal) uri

  (** URI closed with operation documentation. *)
  type ('handler, 'terminal) documented

  (** Documented URI with its request-body contract attached. *)
  type ('handler, 'terminal, 'request) requested

  (** Complete endpoint declaration ready to receive its handler. *)
  type ('handler, 'terminal, 'request) ready

  (** Starts a path for an arbitrary backend method. *)
  val meth : Method.t -> ([ `Path ], 'terminal, 'terminal) uri

  (** Starts a GET route. *)
  val get : ([ `Path ], 'terminal, 'terminal) uri

  (** Starts a POST route. *)
  val post : ([ `Path ], 'terminal, 'terminal) uri

  (** Starts a PUT route. *)
  val put : ([ `Path ], 'terminal, 'terminal) uri

  (** Starts a DELETE route. *)
  val delete : ([ `Path ], 'terminal, 'terminal) uri

  (** Starts a PATCH route. *)
  val patch : ([ `Path ], 'terminal, 'terminal) uri

  (** Appends a static segment. Static and captured segments are no
            longer accepted after the first query parameter. *)
  val ( / )
    :  ([ `Path ], 'handler, 'terminal) uri
    -> string
    -> ([ `Path ], 'handler, 'terminal) uri

  (** Appends a required captured path segment. *)
  val ( /: )
    :  ([ `Path ], 'handler, 'value -> 'terminal) uri
    -> 'value argument
    -> ([ `Path ], 'handler, 'terminal) uri

  (** Appends an optional query parameter. *)
  val ( /? )
    :  ([< `Path | `Query ], 'handler, 'value option -> 'terminal) uri
    -> 'value argument
    -> ([ `Query ], 'handler, 'terminal) uri

  (** Appends a required query parameter. *)
  val ( /! )
    :  ([< `Path | `Query ], 'handler, 'value -> 'terminal) uri
    -> 'value argument
    -> ([ `Query ], 'handler, 'terminal) uri

  (** Appends a required or optional typed request header. Path and query
            operators are no longer available after this stage. *)
  val header
    :  'value Header.t
    -> ([< `Path | `Query | `Header ], 'handler, 'value -> 'terminal) uri
    -> ([ `Header ], 'handler, 'terminal) uri

  (** Closes URI construction and records endpoint metadata. *)
  val documented
    :  ?summary:string
    -> ?tags:string list
    -> ?deprecated:bool
    -> ?operation_id:string
    -> ?description:string
    -> ?decode_error:Decode_error_response.t
    -> ([< `Path | `Query | `Header ], 'handler, 'terminal) uri
    -> ('handler, 'terminal) documented

  (** Adds the only request-body declaration and advances to responses. *)
  val accepts
    :  'request Request.t
    -> ('handler, 'terminal) documented
    -> ('handler, 'terminal, 'request) requested

  (** Adds one or more typed response cases and advances to a
            handler-ready route. *)
  val returns
    :  ('response_handler, 'terminal) responses
    -> ('handler, 'response_handler, 'request) requested
    -> ('handler, 'terminal, 'request) ready

  (** Finalizes a route whose handler receives no explicit context. *)
  val handle : 'handler -> ('handler, 'request -> reply B.io, 'request) ready -> route

  (** Finalizes a route and supplies a typed context to its handler. *)
  val handle_with
    :  context:'context Context.t
    -> 'handler
    -> ('handler, 'context -> 'request -> reply B.io, 'request) ready
    -> route

  (** Infix finalizer for grouped routes. *)
  val ( ==> )
    :  ('handler, 'context -> 'request -> reply B.io, 'request) ready
    -> 'handler
    -> 'context Group.route

  (** Escape hatch for backend-specific routes excluded from the contract. *)
  module Unsafe : sig
    (** Adds a runtime-only route that is deliberately absent from OpenAPI. *)
    val route : meth:Method.t -> path:string -> handler:(B.req -> B.resp B.io) -> route
  end

  (** Errors that prevent route compilation. *)
  module Compile_error : sig
    (** Static contract violations found before a backend application or
            OpenAPI document is exposed. Errors are accumulated when possible. *)
    type t =
      | Duplicate_route of
          { meth : string
          ; path : string
          }
      | Ambiguous_route of
          { meth : string
          ; path : string
          ; conflicts_with : string
          }
      (** A route has the same method and capture shape as another route,
              so neither a runtime router nor OpenAPI can distinguish them. *)
      | Invalid_group_prefix_segment of string
      (** A group prefix is not a single static URL segment. *)
      | Invalid_route_path of
          { meth : string
          ; path : string
          } (** A typed route is not canonical or contains wildcard syntax. *)
      | Mismatched_path_parameters of
          { meth : string
          ; path : string
          ; declared : string list
          ; captures : string list
          } (** The rendered capture names differ from the typed parameters. *)
      | Duplicate_operation_id of string
      | Duplicate_parameter of
          { meth : string
          ; path : string
          ; kind : [ `Path | `Query | `Header ]
          ; name : string
          } (** One endpoint repeats a parameter name in the same location. *)
      | Duplicate_response_status of
          { meth : string
          ; path : string
          ; status : int
          }
      | Invalid_response_status of
          { meth : string
          ; path : string
          ; status : int
          } (** A declared status is outside the HTTP range 100 through 599. *)
      | Invalid_no_content_response of
          { meth : string
          ; path : string
          }
      | Invalid_body_limit of
          { meth : string
          ; path : string
          ; max_body_bytes : int
          }
      | Invalid_header_name of
          { meth : string
          ; path : string
          ; name : string
          }
      | Duplicate_response_header of
          { meth : string
          ; path : string
          ; status : int
          ; name : string
          }
      | Conflicting_response_header of
          { meth : string
          ; path : string
          ; status : int
          ; name : string
          }
      | Invalid_schema_name of string
      | Conflicting_schema of string
      | Invalid_security_scheme_name of string
      | Conflicting_security_scheme of string
      | Invalid_security_scope of
          { scheme : string
          ; scope : string
          }

    (** Stable human-readable diagnostic suitable for startup logs. *)
    val to_string : t -> string
  end

  (** Successfully validated routes ready for backend and OpenAPI rendering. *)
  module Compiled : sig
    (** Abstract compiled contract and runtime route collection. *)
    type t

    (** Builds the backend-specific runtime application. *)
    val app : t -> B.app_builder

    (** Renders the OpenAPI document from the compiled contract. *)
    val openapi : ?config:Openapi.Config.t -> t -> Yojson.Safe.t
  end

  (** Validates route declarations and produces their common contract.
          Endpoint decode-error policies take precedence over group policies, which
          take precedence over [decode_error]. When none is supplied, the safe
          {!Decode_error_response.default} policy is used. Runtime routes are
          ordered by specificity, so a static segment takes precedence over a
          capture at the same position regardless of declaration order. *)
  val compile
    :  ?decode_error:Decode_error_response.t
    -> ?interceptors:interceptor list
    -> Group.t list
    -> (Compiled.t, Compile_error.t list) Result.t

  (** Like [compile], but raises [Failure] with all validation errors. *)
  val compile_exn
    :  ?decode_error:Decode_error_response.t
    -> ?interceptors:interceptor list
    -> Group.t list
    -> Compiled.t
end
