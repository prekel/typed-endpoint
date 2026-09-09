open! Base

module Metadata : sig
  (** Metadata keeps a schema tied to the OCaml wire type. [schema_name], when
      present, registers the schema in OpenAPI [components/schemas] and renders
      references to it. Reusing a name for a different schema is a compile error. *)
  type 'a t = private
    { schema : Ppx_deriving_jsonschema_runtime.t
    ; schema_name : string option
    ; description : string
    ; tags : string list
    }

  (** Creates metadata for exactly ['a]. [schema_name] opts into a reusable
      OpenAPI component; names are validated during compilation. *)
  val v
    :  schema:Ppx_deriving_jsonschema_runtime.t
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
    type t =
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

    (** Structural equality of the component name, description, and kind. *)
    val equal : t -> t -> bool
  end

  (** Schemes in one requirement must all be satisfied (AND). Scope lists are
      valid only for OAuth 2 schemes and are validated during compilation. *)
  type requirement = (Scheme.t * string list) list

  (** Creates a one-scheme requirement. [scopes] defaults to the empty list. *)
  val require : ?scopes:string list -> Scheme.t -> requirement

  (** Conjoins requirements, merging repeated identical schemes and
      deduplicating their scopes. *)
  val all : requirement list -> requirement

  (** Conjoins two sets of alternatives by taking their Cartesian product.
      An empty argument acts as the identity, which makes this suitable for
      adding optional group-level requirements. *)
  val combine_alternatives : requirement list -> requirement list -> requirement list
end

(** An authenticated identity together with the scopes granted for the current
    request. The identity type belongs to the application; the HTTP core only
    carries it and never performs runtime type lookup. *)
module Principal : sig
  type 'identity t = private
    { identity : 'identity
    ; scopes : string list
    }

  (** Creates a principal with a deterministic, duplicate-free scope list. *)
  val v : ?scopes:string list -> identity:'identity -> unit -> 'identity t

  val identity : 'identity t -> 'identity
  val scopes : _ t -> string list
  val has_scope : _ t -> string -> bool
end

(** Stable, low-cardinality metadata for one matched runtime route.
    [path_template] uses OpenAPI-style captures such as [/pet/{petId}], never
    the raw request target. *)
module Route_info : sig
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

    (** Minimal configuration with title ["API"] and version ["0.1.0"]. *)
    val default : t
  end
end

module Operation_metadata : sig
  (** Documentation attached to an OpenAPI operation or inherited from a route
      group. Group tags are prepended to endpoint tags. *)
  type t =
    { description : string
    ; summary : string option
    ; tags : string list
    ; deprecated : bool
    ; operation_id : string option
    }

  (** Creates operation metadata. Optional fields preserve the distinction
      between absent documentation and an explicitly empty value. *)
  val v
    :  ?summary:string
    -> ?tags:string list
    -> ?deprecated:bool
    -> ?operation_id:string
    -> description:string
    -> unit
    -> t
end

(** A wire type carrying the schema and documentation used by OpenAPI. Keeping
    the metadata typed prevents accidentally passing metadata for another DTO. *)
module type Metadatable = sig
  type t

  (** The runtime JSON shape and documentation for [t]. *)
  val metadata : t Metadata.t
end

module Backend : sig
  (** Minimal capability contract implemented by each HTTP adapter. Application
      code normally consumes an existing backend rather than implementing this
      signature directly. *)
  module type S = sig
    (** Native request and response values owned by the HTTP framework. *)
    type req

    type resp

    (** Backend effect. Lwt adapters use [type 'a io = 'a Lwt.t]; direct-style
        Eio uses the identity type. *)
    type 'a io

    (** Lawful sequencing operations for [io]. Besides [return], [bind], and
        [map], this exposes [Let_syntax] for backend-independent [let%bind] and
        [let%map]. Derived collection combinators execute sequentially. *)
    module Io : Base.Monad.S with type 'a t = 'a io

    (** Methods understood by the runtime router. [`Other] preserves extension
        methods for unsafe runtime-only routes. *)
    type meth =
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

    (** Typed status families used by response declarations. *)
    type informational_status =
      [ `Continue
      | `Switching_protocols
      | `Processing
      | `Checkpoint
      ]

    type success_status =
      [ `OK
      | `Created
      | `Accepted
      | `Non_authoritative_information
      | `No_content
      | `Reset_content
      | `Partial_content
      | `Multi_status
      | `Already_reported
      | `Im_used
      ]

    type redirection_status =
      [ `Multiple_choices
      | `Moved_permanently
      | `Found
      | `See_other
      | `Not_modified
      | `Use_proxy
      | `Switch_proxy
      | `Temporary_redirect
      | `Permanent_redirect
      ]

    type client_error_status =
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

    type server_error_status =
      [ `Internal_server_error
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

    type status =
      [ informational_status
      | success_status
      | redirection_status
      | client_error_status
      | server_error_status
      ]

    type status_code =
      [ `Code of int
      | status
      ]

    (** Returns the numeric HTTP status, including custom [`Code] values. *)
    val code_of_status : status_code -> int

    (** A backend router value accumulated by {!combine}. *)
    type app_builder

    (** The only expected failure of bounded body reads. *)
    type body_read_error = [ `Too_large ]

    (** Canonical method values used by the endpoint DSL. *)
    val get : meth

    val post : meth
    val put : meth
    val delete : meth
    val patch : meth

    (** Registers one already-rendered backend path and handler. *)
    val route : meth -> string -> (req -> resp io) -> app_builder

    (** Retrieves a router-decoded path capture. *)
    val param : req -> string -> string

    (** Retrieves one optional query value. *)
    val query : req -> string -> string option

    (** Header lookup is case-insensitive in HTTP backends. *)
    val header : req -> string -> string option

    (** Reads at most [max_bytes]. Backends must stop buffering once the limit
        is exceeded and return [`Too_large]. *)
    val body_to_string : max_bytes:int -> req -> (string, body_read_error) Result.t io

    (** Creates a response without a representation or [Content-Type]. An
        omitted status means HTTP 200. *)
    val respond_empty : ?status:status_code -> unit -> resp io

    (** Creates a [text/plain; charset=utf-8] response. An omitted status means
        HTTP 200. *)
    val respond_string : ?status:status_code -> string -> resp io

    (** Creates [text/html; charset=utf-8] and [application/json] responses. *)
    val respond_html : ?status:status_code -> string -> resp io

    val respond_json : ?status:status_code -> Yojson.Safe.t -> resp io

    (** Combines routers while preserving declaration order. Runtime assembly
        places static paths before otherwise overlapping capture paths. *)
    val combine : app_builder -> app_builder -> app_builder

    (** The identity router containing no routes. *)
    val empty : app_builder
  end
end

(** A response returned by a handler violates its declared status contract. *)
module Runtime_error : sig
  type t =
    | Undeclared_status of
        { meth : string
        ; path : string
        ; status : int
        ; declared : int list
        }

  (** Includes the method, path, actual status, and declared status set. *)
  val to_string : t -> string
end

(** Raised when a handler returns a status absent from its response declaration. *)
exception Runtime_error of Runtime_error.t

(** Codecs shared by path and query parameters. A codec is the single source
    for runtime parsing and the parameter's OpenAPI schema. *)
module Parameter : sig
  module type S = sig
    type t

    (** Parses one percent-decoded path or query value. [Error message] becomes
        part of the configured decode-error response. *)
    val of_string : string -> (t, string) Result.t

    include Metadatable with type t := t
  end

  (** Builds a first-class codec without requiring a named module. *)
  val v
    :  schema:Ppx_deriving_jsonschema_runtime.t
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

  val int
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = int)

  val int64
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = int64)

  val float
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = float)

  val bool
    :  ?schema_name:string
    -> ?tags:string list
    -> description:string
    -> unit
    -> (module S with type t = bool)
end

module Request_payload : sig
  (** A JSON request DTO. [of_yojson] runs only after media type, size, and JSON
      syntax checks have succeeded. *)
  module type S = sig
    type t

    include Metadatable with type t := t

    val of_yojson : Yojson.Safe.t -> (t, string) Result.t
  end
end

module Response_payload : sig
  (** A JSON response DTO. The declared schema must describe the value emitted
      by [to_yojson]. *)
  module type S = sig
    type t

    include Metadatable with type t := t

    val to_yojson : t -> Yojson.Safe.t
  end
end

(** Convenience signature for DTOs used in both request and response bodies. *)
module Json_payload : sig
  module type S = sig
    type t

    include Metadatable with type t := t

    val of_yojson : Yojson.Safe.t -> (t, string) Result.t
    val to_yojson : t -> Yojson.Safe.t
  end
end

module Decode_error : sig
  (** Failures produced before the user handler runs. They map to 400, 413, or
      415 according to the constructor; applications control only the JSON
      payload through {!Make.Dsl.Decode_error_response}. *)
  type t =
    | Invalid_parameter of
        { source : [ `Path | `Query ]
        ; name : string
        ; value : string
        ; error : string
        }
    | Missing_parameter of
        { source : [ `Path | `Query ]
        ; name : string
        }
    | Invalid_json of { error : string }
    | Invalid_body of { error : string }
    | Unsupported_media_type of
        { expected : string list
        ; actual : string option
        }
    | Body_too_large of { max_bytes : int }

  include Metadatable with type t := t

  (** Serializes the diagnostic representation. Prefer
      {!Make.Dsl.Decode_error_response.default} for public responses because it
      deliberately omits rejected parameter values. *)
  val to_yojson : t -> Yojson.Safe.t
end

(** Specializes the endpoint DSL to a backend while preserving its native
    effect and application-builder types. *)
module Make
    (B : Backend.S) : sig
    module B : Backend.S

    (** Backend effect operations re-exported for handlers and injected
        services. Open [Io.Let_syntax] to use [ppx_let]. *)
    module Io : Base.Monad.S with type 'a t = 'a B.io

    (** Typed handler result. Each constructor is available only when its
        matching response was declared; dynamic family constructors are also
        checked against their declared numeric status at runtime. *)
    type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp =
      | OK :
          'ok
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
      | Created :
          'created
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
      | No_content :
          ('ok, 'created, unit, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
      | Code_2xx :
          B.success_status * 'code2xx
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
      | Not_found :
          'nf
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
      | Bad_request :
          'bad
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
      | Code_4xx :
          B.client_error_status * 'code4xx
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
      | Internal_server_error :
          'ise
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
      | Code_5xx :
          B.server_error_status * 'code5xx
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
      | Code :
          B.status_code * 'code
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp

    module Dsl : sig
      type never = |

      module Request : sig
        (** Runtime request decoding paired with its OpenAPI request-body
            contract. *)
        type _ t

        (** A request without a body. The handler receives [()]. *)
        val empty : unit t

        (** One mebibyte. *)
        val default_max_body_bytes : int

        (** Requires a JSON media type, reads no more than [max_body_bytes], and
            then invokes the DTO decoder. *)
        val json
          :  ?max_body_bytes:int
          -> (module Request_payload.S with type t = 'a)
          -> 'a t

        (** A UTF-8 text body requiring [Content-Type: text/plain]. *)
        val text : ?max_body_bytes:int -> description:string -> unit -> string t

        (** An opaque byte string requiring
            [Content-Type: application/octet-stream]. The backend enforces
            [max_body_bytes] before returning the body. *)
        val binary : ?max_body_bytes:int -> description:string -> unit -> string t
      end

      module Response : sig
        (** Runtime response encoding paired with its OpenAPI content contract. *)
        type 'a t

        (** Declares the exact JSON wire type returned by the handler. *)
        val json : (module Response_payload.S with type t = 'a) -> 'a t

        (** Declares a [text/plain] response. *)
        val text : description:string -> unit -> string t

        (** Declares arbitrary JSON when a statically typed DTO is impractical. *)
        val json_raw : description:string -> unit -> Yojson.Safe.t t

        (** Declares a body-less response. This is normally used with
            {!no_content}. *)
        val empty : description:string -> unit -> unit t
      end

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
          val return : 'a -> 'a t
          val ( >>| ) : 'a t -> ('a -> 'b) -> 'b t
          val ( <*> ) : ('a -> 'b) t -> 'a t -> 'b t
          val ( *> ) : unit t -> 'a t -> 'a t
          val ( <* ) : 'a t -> unit t -> 'a t

          module Let_syntax : sig
            val return : 'a -> 'a t
            val map : 'a t -> f:('a -> 'b) -> 'b t
            val both : 'a t -> 'b t -> ('a * 'b) t

            module Open_on_rhs : sig end
          end
        end

        (** The raw backend request. Pass it to {!Staged.handle_with} explicitly
            when framework-neutral dependencies are insufficient. *)
        val request : B.req t

        (** A context carrying no request data. It is equivalent to [return ()]. *)
        val empty : unit t
      end

      module Dependency : sig
        (** Injects an immutable application dependency into every request. *)
        val value : 'a -> 'a Context.t

        (** Resolves a request-scoped dependency before request decoding. *)
        val of_request : (B.req -> 'a B.io) -> 'a Context.t
      end

      module Guard : sig
        (** Builds a guard whose successful typed context is passed to the handler.
            Rejections are rendered with [response] and included in OpenAPI.
            Entries in [security] are OpenAPI alternatives (OR). Compose guards
            with {!Context.both} to require all of them (AND). *)
        val v
          :  ?security:Security.requirement list
          -> status:B.client_error_status
          -> response:'error Response.t
          -> check:(B.req -> ('context, 'error) Result.t B.io)
          -> unit
          -> 'context Context.t

        (** Authentication-specific name for {!v}. A successful check returns
            a typed principal which can be combined with request-scoped
            dependencies through {!Context}. *)
        val authenticate
          :  ?security:Security.requirement list
          -> status:B.client_error_status
          -> response:'error Response.t
          -> check:(B.req -> ('identity Principal.t, 'error) Result.t B.io)
          -> unit
          -> 'identity Principal.t Context.t
      end

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

      (** Internal response-list index exposed abstractly so declarations remain
          type safe while response combinators compose. *)
      type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** A response declaration function. Each phantom slot corresponds to one
          handler-result constructor family. *)
      type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) responses =
        (never, never, never, never, never, never, never, never, never) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Combines response declarations from left to right. Duplicate status
          declarations are rejected during compilation. *)
      val ( |+ )
        :  (('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h, 'i) rb
            -> ('j, 'k, 'l, 'm, 'n, 'o, 'p, 'q, 'r) rb)
        -> (('s, 't, 'u, 'v, 'w, 'x, 'y, 'z, 'a1) rb
            -> ('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h, 'i) rb)
        -> ('s, 't, 'u, 'v, 'w, 'x, 'y, 'z, 'a1) rb
        -> ('j, 'k, 'l, 'm, 'n, 'o, 'p, 'q, 'r) rb

      (** Choice-shaped alias for [|+], intended for the staged DSL. *)
      val ( <|> )
        :  (('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h, 'i) rb
            -> ('j, 'k, 'l, 'm, 'n, 'o, 'p, 'q, 'r) rb)
        -> (('s, 't, 'u, 'v, 'w, 'x, 'y, 'z, 'a1) rb
            -> ('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h, 'i) rb)
        -> ('s, 't, 'u, 'v, 'w, 'x, 'y, 'z, 'a1) rb
        -> ('j, 'k, 'l, 'm, 'n, 'o, 'p, 'q, 'r) rb

      module JSON : sig
        (** Shorthand response declarations equivalent to applying
            {!Response.json} before the status-specific combinator. *)
        val ok
          :  (module Response_payload.S with type t = 'ok)
          -> (never, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

        val created
          :  (module Response_payload.S with type t = 'created)
          -> ('ok, never, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

        val bad_request
          :  (module Response_payload.S with type t = 'bad)
          -> ('ok, 'created, 'code2xx, 'nf, never, 'code4xx, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

        val not_found
          :  (module Response_payload.S with type t = 'nf)
          -> ('ok, 'created, 'code2xx, never, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

        val internal_server_error
          :  (module Response_payload.S with type t = 'ise)
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, never, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

        (** JSON shorthand for a set of client-error statuses. *)
        val client_errors
          :  B.client_error_status list
          -> (module Response_payload.S with type t = 'code4xx)
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, never, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

        (** JSON shorthand for a set of server-error statuses. *)
        val server_errors
          :  B.server_error_status list
          -> (module Response_payload.S with type t = 'code5xx)
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, never, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      end

      (** Declares a non-empty set of successful statuses sharing one payload.
          The selected {!Code_2xx} status is checked at runtime. *)
      val code2xx
        :  B.success_status list
        -> 'code2xx Response.t
        -> ('ok, 'created, never, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Declares the only body-less successful response, HTTP 204. *)
      val no_content
        :  description:string
        -> ('ok, 'created, never, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, unit, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Declares a non-empty set of client-error statuses sharing one payload. *)
      val code4xx
        :  B.client_error_status list
        -> 'code4xx Response.t
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, never, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Declares a non-empty set of server-error statuses sharing one payload. *)
      val code5xx
        :  B.server_error_status list
        -> 'code5xx Response.t
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, never, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Declares arbitrary explicit status codes sharing one payload. *)
      val code
        :  B.status_code list
        -> 'code Response.t
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, never) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Declares HTTP 200 and enables the {!OK} result constructor. *)
      val ok
        :  'ok Response.t
        -> (never, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Declares HTTP 201 and enables the {!Created} result constructor. *)
      val created
        :  'created Response.t
        -> ('ok, never, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Declares HTTP 404 and enables the {!Not_found} result constructor. *)
      val not_found
        :  'nf Response.t
        -> ('ok, 'created, 'code2xx, never, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Declares HTTP 400 and enables the {!Bad_request} result constructor. *)
      val bad_request
        :  'bad Response.t
        -> ('ok, 'created, 'code2xx, 'nf, never, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      (** Declares HTTP 500 and enables the {!Internal_server_error} result
          constructor. *)
      val internal_server_error
        :  'ise Response.t
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, never, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      module Route : sig
        (** An existential route whose handler types remain checked at creation. *)
        type t
      end

      module Interceptor : sig
        (** A route-aware runtime wrapper. It runs only after a route has
            matched, receives stable contract metadata, and deliberately has no
            application dependency store. The first interceptor in a compile
            list is the outermost wrapper. *)
        type t =
          route_info:Route_info.t
          -> request:B.req
          -> next:(unit -> B.resp B.io)
          -> B.resp B.io
      end

      module Group : sig
        type t

        (** An endpoint declaration waiting for a group-owned context. The type
            parameter makes it impossible to attach a context of another type. *)
        type 'context route

        (** [decode_error] overrides the application policy for every fallible route
            in the group unless the endpoint has its own override. *)
        val v
          :  ?prefix:string list
          -> ?decode_error:Decode_error_response.t
          -> metadata:Operation_metadata.t
          -> Route.t list
          -> t

        (** Convenience constructor that creates {!Operation_metadata.t}
            inline. Prefer this when metadata is not shared elsewhere. *)
        val make
          :  ?prefix:string list
          -> ?decode_error:Decode_error_response.t
          -> ?summary:string
          -> ?tags:string list
          -> ?deprecated:bool
          -> description:string
          -> Route.t list
          -> t

        (** Contextual counterpart of {!v} for callers that already have a
            reusable metadata value. *)
        val v_with_context
          :  ?prefix:string list
          -> ?decode_error:Decode_error_response.t
          -> metadata:Operation_metadata.t
          -> context:'context Context.t
          -> 'context route list
          -> t

        (** Attaches one typed context to every route finalized with
            {!Staged.handle_in_group}. The context is resolved only for the
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

      (** The URI-first endpoint DSL. Its abstract phase types enforce the
          declaration order path -> query -> documentation -> request ->
          responses -> handler. *)
      module Staged : sig
        (** A named typed path or query argument. The operator determines its
            location and whether it is optional. *)
        type 'a argument

        val arg : string -> (module Parameter.S with type t = 'a) -> 'a argument

        type ('phase, 'handler, 'terminal) uri
        type ('handler, 'terminal) documented
        type ('handler, 'terminal, 'request) requested

        type ('handler
             , 'terminal
             , 'request
             , 'ok
             , 'created
             , 'code2xx
             , 'not_found
             , 'bad_request
             , 'code4xx
             , 'internal_server_error
             , 'code5xx
             , 'code)
             ready

        (** Starts a path for an arbitrary backend method. *)
        val meth : B.meth -> ([ `Path ], 'terminal, 'terminal) uri

        val get : ([ `Path ], 'terminal, 'terminal) uri
        val post : ([ `Path ], 'terminal, 'terminal) uri
        val put : ([ `Path ], 'terminal, 'terminal) uri
        val delete : ([ `Path ], 'terminal, 'terminal) uri
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

        (** Closes URI construction and records endpoint metadata. *)
        val documented
          :  ?summary:string
          -> ?tags:string list
          -> ?deprecated:bool
          -> ?operation_id:string
          -> ?description:string
          -> ?decode_error:Decode_error_response.t
          -> unit
          -> ([< `Path | `Query ], 'handler, 'terminal) uri
          -> ('handler, 'terminal) documented

        (** Adds the only request-body declaration and advances to responses. *)
        val accepts
          :  'request Request.t
          -> ('handler, 'terminal) documented
          -> ('handler, 'terminal, 'request) requested

        (** Adds the response algebra and advances to a handler-ready route. *)
        val returns
          :  ( 'ok
               , 'created
               , 'code2xx
               , 'not_found
               , 'bad_request
               , 'code4xx
               , 'internal_server_error
               , 'code5xx
               , 'code )
               responses
          -> ('handler, 'terminal, 'request) requested
          -> ( 'handler
               , 'terminal
               , 'request
               , 'ok
               , 'created
               , 'code2xx
               , 'not_found
               , 'bad_request
               , 'code4xx
               , 'internal_server_error
               , 'code5xx
               , 'code )
               ready

        val handle
          :  ( 'handler
               , 'request
                 -> ( 'ok
                      , 'created
                      , 'code2xx
                      , 'not_found
                      , 'bad_request
                      , 'code4xx
                      , 'internal_server_error
                      , 'code5xx
                      , 'code )
                      resp
                      B.io
               , 'request
               , 'ok
               , 'created
               , 'code2xx
               , 'not_found
               , 'bad_request
               , 'code4xx
               , 'internal_server_error
               , 'code5xx
               , 'code )
               ready
          -> 'handler
          -> Route.t

        val handle_with
          :  context:'context Context.t
          -> ( 'handler
               , 'context
                 -> 'request
                 -> ( 'ok
                      , 'created
                      , 'code2xx
                      , 'not_found
                      , 'bad_request
                      , 'code4xx
                      , 'internal_server_error
                      , 'code5xx
                      , 'code )
                      resp
                      B.io
               , 'request
               , 'ok
               , 'created
               , 'code2xx
               , 'not_found
               , 'bad_request
               , 'code4xx
               , 'internal_server_error
               , 'code5xx
               , 'code )
               ready
          -> 'handler
          -> Route.t

        val handle_in_group
          :  ( 'handler
               , 'context
                 -> 'request
                 -> ( 'ok
                      , 'created
                      , 'code2xx
                      , 'not_found
                      , 'bad_request
                      , 'code4xx
                      , 'internal_server_error
                      , 'code5xx
                      , 'code )
                      resp
                      B.io
               , 'request
               , 'ok
               , 'created
               , 'code2xx
               , 'not_found
               , 'bad_request
               , 'code4xx
               , 'internal_server_error
               , 'code5xx
               , 'code )
               ready
          -> 'handler
          -> 'context Group.route

        (** Infix finalizer for grouped routes. *)
        val ( ==> )
          :  ( 'handler
               , 'context
                 -> 'request
                 -> ( 'ok
                      , 'created
                      , 'code2xx
                      , 'not_found
                      , 'bad_request
                      , 'code4xx
                      , 'internal_server_error
                      , 'code5xx
                      , 'code )
                      resp
                      B.io
               , 'request
               , 'ok
               , 'created
               , 'code2xx
               , 'not_found
               , 'bad_request
               , 'code4xx
               , 'internal_server_error
               , 'code5xx
               , 'code )
               ready
          -> 'handler
          -> 'context Group.route
      end

      module Unsafe : sig
        (** Adds a runtime-only route that is deliberately absent from OpenAPI. *)
        val route
          :  meth:B.meth
          -> path:string
          -> handler:(B.req -> B.resp B.io)
          -> Route.t
      end

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
              ; kind : [ `Path | `Query ]
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
          | Empty_response_family of
              { meth : string
              ; path : string
              }
          | Invalid_no_content_response of
              { meth : string
              ; path : string
              }
          | Invalid_body_limit of
              { meth : string
              ; path : string
              ; max_body_bytes : int
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

      module Compiled : sig
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
        -> ?interceptors:Interceptor.t list
        -> Group.t list
        -> (Compiled.t, Compile_error.t list) Result.t

      (** Like [compile], but raises [Failure] with all validation errors. *)
      val compile_exn
        :  ?decode_error:Decode_error_response.t
        -> ?interceptors:Interceptor.t list
        -> Group.t list
        -> Compiled.t
    end
  end
  with module B = B
