open! Base

(** Human-readable documentation attached to a parameter, body, or response.
    These values affect the generated OpenAPI document and have no runtime
    decoding semantics. *)
module Documentation : sig
  (** [description] explains the value at its point of use. [tags] are retained
      with the contract for consumers that want to classify the value. *)
  type t =
    { description : string
    ; tags : string list
    }

  (** [v ~description ()] creates documentation with no tags unless [tags] is
      supplied. *)
  val v : ?tags:string list -> description:string -> unit -> t
end

(** Documentation that describes an OpenAPI operation or a route group. *)
module Operation_metadata : sig
  (** [operation_id], when present, must be unique in the compiled API.
      Endpoint metadata replaces the group's description, summary, deprecation
      flag, and operation id; group and endpoint tags are combined. *)
  type t =
    { description : string
    ; summary : string option
    ; tags : string list
    ; deprecated : bool
    ; operation_id : string option
    }

  (** Creates operation metadata. [deprecated] defaults to [false], and [tags]
      defaults to the empty list. *)
  val v
    :  ?summary:string
    -> ?tags:string list
    -> ?deprecated:bool
    -> ?operation_id:string
    -> description:string
    -> unit
    -> t
end

(** A JSON Schema together with its optional OpenAPI component identity. *)
module Schema : sig
  (** A named schema is emitted under [components/schemas] and referenced from
      its uses. Component names must be non-empty and contain only letters,
      digits, dots, underscores, or hyphens. Reusing a name with a different
      schema is rejected by {!compile}. An unnamed schema is rendered inline. *)
  type t =
    { value : Json_schema.t
    ; name : string option
    }

  (** Associates an optional component [name] with a JSON Schema value. *)
  val v : ?name:string -> Json_schema.t -> t

  (** Structural equality of both the optional name and JSON Schema value. *)
  val equal : t -> t -> bool
end

(** OpenAPI authentication schemes and operation security requirements.

    A {!requirement} is a conjunction (AND) of schemes. The [security] field of
    an endpoint is a list of alternatives (OR), matching OpenAPI's security
    requirement semantics. *)
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

(** Settings used while rendering the OpenAPI document. *)
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

(** The source from which a textual route parameter is decoded. *)
type param_kind =
  [ `Path
  | `Query
  | `Header
  ]

(** The documentation contract for a path, query, or header parameter. Path
    parameters are required by construction; query and header parameters may
    be optional. [schema] describes the value after decoding. *)
type param =
  { name : string
  ; kind : param_kind
  ; required : bool
  ; schema : Schema.t
  ; metadata : Documentation.t
  }

(** The request entity accepted by an endpoint.

    JSON and text bodies are required when declared. [max_body_bytes] is a
    strict positive upper bound that the backend must enforce while reading,
    before unbounded buffering can occur. *)
type request_body =
  | No_body (** The endpoint does not consume a request entity. *)
  | Json_body of
      { schema : Schema.t
      ; metadata : Documentation.t
      ; max_body_bytes : int
      } (** An [application/json] entity decoded according to [schema]. *)
  | Text_body of
      { metadata : Documentation.t
      ; max_body_bytes : int
      } (** A [text/plain] entity passed to the request decoder as text. *)
  | Binary_body of
      { metadata : Documentation.t
      ; max_body_bytes : int
      }
  (** An [application/octet-stream] entity represented as an OCaml string
            of bytes. *)

(** A response representation advertised for one status code. [Json] accepts
    multiple schemas because independently introduced responses for the same
    status are merged and rendered as an OpenAPI [oneOf]. *)
type response_content =
  | Text
  | Json of Schema.t list

(** One response header declared for a status. Header names are compared
    case-insensitively during validation, while [name] is retained for OpenAPI
    rendering. *)
type response_header =
  { name : string
  ; required : bool
  ; schema : Schema.t
  ; metadata : Documentation.t
  }

(** Documentation and all media representations for one response status. An
    empty [content] denotes a response without a body, as required for 204. *)
type response_payload =
  { metadata : Documentation.t
  ; content : response_content list
  ; headers : response_header list
  }

(** A concrete HTTP status and its wire payload contract. A status may occur at
    most once in an endpoint's explicit [responses] list. *)
type response =
  { status : int
  ; payload : response_payload
  }

(** Complete backend-independent contract for a typed endpoint.

    [decode_error_responses] and [context_responses] are implicit failure
    responses. Compilation merges them into [responses] by status and media
    type. [security] is an OR-list of security requirements. *)
type endpoint =
  { meth : string
  ; path : string
  ; metadata : Operation_metadata.t option
  ; params : param list
  ; request_body : request_body
  ; responses : response list
  ; decode_error_responses : response list
  ; context_responses : response list
  ; security : Security.requirement list
  }

(** A route before group compilation. [path] does not yet include the group's
    prefix. [endpoint = None] represents an unsafe, runtime-only route; it still
    participates in duplicate-route validation but is omitted from OpenAPI. *)
type route =
  { meth : string
  ; path : string
  ; endpoint : endpoint option
  }

(** A collection of routes that share path-prefix segments and documentation.
    Group metadata is inherited by operations that do not provide their own
    metadata. *)
type group =
  { prefix : string list
  ; metadata : Operation_metadata.t
  ; routes : route list
  }

(** Static contract errors collected before a backend application or OpenAPI
    document is exposed. Compilation reports all detected errors, rather than
    stopping at the first one. *)
module Compile_error : sig
  type t =
    | Duplicate_route of
        { meth : string
        ; path : string
        } (** Two routes use the same HTTP method and fully prefixed path. *)
    | Ambiguous_route of
        { meth : string
        ; path : string
        ; conflicts_with : string
        }
    (** Two routes use the same method and matching shape, but give a path
        capture different names. Such routes are indistinguishable at runtime
        and forbidden by OpenAPI. *)
    | Invalid_group_prefix_segment of string
    (** A group prefix contains an empty segment, a slash, a router capture or
        wildcard marker, or a dot-navigation segment. *)
    | Invalid_route_path of
        { meth : string
        ; path : string
        } (** A typed route is not canonical or contains router wildcard syntax. *)
    | Mismatched_path_parameters of
        { meth : string
        ; path : string
        ; declared : string list
        ; captures : string list
        } (** The rendered capture names differ from the typed path parameters. *)
    | Duplicate_operation_id of string
    (** An explicit OpenAPI [operationId] is reused by another endpoint. *)
    | Duplicate_parameter of
        { meth : string
        ; path : string
        ; kind : param_kind
        ; name : string
        }
    (** One endpoint declares the same parameter name more than once in the
        same path or query location. *)
    | Duplicate_response_status of
        { meth : string
        ; path : string
        ; status : int
        } (** One endpoint explicitly declares the same status more than once. *)
    | Invalid_response_status of
        { meth : string
        ; path : string
        ; status : int
        } (** An explicit response status is outside the HTTP range 100 through 599. *)
    | Invalid_no_content_response of
        { meth : string
        ; path : string
        } (** Status 204 was associated with a text or JSON representation. *)
    | Invalid_body_limit of
        { meth : string
        ; path : string
        ; max_body_bytes : int
        } (** A JSON or text request-body limit is zero or negative. *)
    | Invalid_header_name of
        { meth : string
        ; path : string
        ; name : string
        } (** A request or response header name is not an RFC token. *)
    | Duplicate_response_header of
        { meth : string
        ; path : string
        ; status : int
        ; name : string
        } (** One response declares the same case-insensitive header name twice. *)
    | Conflicting_response_header of
        { meth : string
        ; path : string
        ; status : int
        ; name : string
        } (** Explicit and implicit responses for one status disagree about a header. *)
    | Invalid_schema_name of string
    (** A schema component name is empty or contains an unsupported character. *)
    | Conflicting_schema of string
    (** The same schema component name denotes different JSON Schemas. *)
    | Invalid_security_scheme_name of string
    (** A security-scheme component name is empty or invalid. *)
    | Conflicting_security_scheme of string
    (** The same security-scheme name denotes different definitions. *)
    | Invalid_security_scope of
        { scheme : string
        ; scope : string
        }
    (** A requirement references an undeclared OAuth 2 scope, or attaches a
        scope to a scheme kind that does not support scopes. *)

  (** Returns a stable, human-readable diagnostic for a compile error. *)
  val to_string : t -> string
end

(** A validated and normalized contract suitable for both OpenAPI rendering and
    backend application construction. *)
module Compiled : sig
  (** A route with its group prefix applied to [path]. Unsafe routes retain
      [endpoint = None]. *)
  type compiled_route =
    { meth : string
    ; path : string
    ; endpoint : endpoint option
    }

  (** Group documentation paired with its normalized routes. *)
  type compiled_group =
    { metadata : Operation_metadata.t
    ; routes : compiled_route list
    }

  (** The abstract result of successful compilation. It owns the normalized
    groups and the deduplicated named schema and security components. *)
  type t

  (** Returns groups in declaration order; routes also retain declaration
      order. *)
  val groups : t -> compiled_group list

  (** Returns named component schemas, sorted by component name. Unnamed schemas
      are rendered inline and are not included. *)
  val schemas : t -> Schema.t list

  (** Returns deduplicated security schemes, sorted by component name. *)
  val security_schemes : t -> Security.Scheme.t list
end

(** Joins path-prefix segments with slashes. The empty prefix becomes [""], and
    a non-empty prefix receives one leading slash. Segments are not escaped or
    normalized. *)
val prefix_to_string : string list -> string

(** Joins an already rendered route [path] to [prefix]. A root path becomes the
    prefix itself, avoiding an adapter-dependent trailing slash. *)
val full_path : prefix:string -> string -> string

(** Validates groups, applies group prefixes, normalizes a prefixed root route,
    verifies rendered captures against typed path parameters, merges implicit
    responses, and registers named schema and security components. *)
val compile : group list -> (Compiled.t, Compile_error.t list) Result.t

(** Equivalent to {!compile}, raising [Failure] with all diagnostics joined by
    semicolons when validation fails. *)
val compile_exn : group list -> Compiled.t
