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
module Security = Contract.Security

(** OpenAPI document configuration shared by all backends. *)
module Openapi = Contract.Openapi

module Operation_metadata : sig
  type t =
    { description : string
    ; summary : string option
    ; tags : string list
    ; deprecated : bool
    ; operation_id : string option
    }

  val v
    :  ?summary:string
    -> ?tags:string list
    -> ?deprecated:bool
    -> ?operation_id:string
    -> description:string
    -> unit
    -> t
end

module type Metadatable = sig
  type t

  val metadata : t Metadata.t
end

module Backend : sig
  module type S = sig
    type req
    type resp

    (** Backend effect. Lwt adapters use [type 'a io = 'a Lwt.t]; direct-style
        Eio uses the identity type. *)
    type 'a io

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

    val code_of_status : status_code -> int

    type app_builder
    type body_read_error = [ `Too_large ]

    val get : meth
    val post : meth
    val put : meth
    val delete : meth
    val patch : meth
    val return : 'a -> 'a io
    val bind : 'a io -> f:('a -> 'b io) -> 'b io
    val route : meth -> string -> (req -> resp io) -> app_builder
    val param : req -> string -> string
    val query : req -> string -> string option

    (** Header lookup is case-insensitive in HTTP backends. *)
    val header : req -> string -> string option

    (** Reads at most [max_bytes]. Backends must stop buffering once the limit
        is exceeded and return [`Too_large]. *)
    val body_to_string : max_bytes:int -> req -> (string, body_read_error) Result.t io

    val respond_string : ?status:status_code -> string -> resp io
    val respond_html : ?status:status_code -> string -> resp io
    val respond_json : ?status:status_code -> Yojson.Safe.t -> resp io
    val combine : app_builder -> app_builder -> app_builder
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

  val to_string : t -> string
end

(** Raised when a handler returns a status absent from its response declaration. *)
exception Runtime_error of Runtime_error.t

module Param : sig
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t

    include Metadatable with type t := t
  end
end

module Query : sig
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t

    include Metadatable with type t := t
  end
end

module Request_payload : sig
  module type S = sig
    type t

    include Metadatable with type t := t

    val of_yojson : Yojson.Safe.t -> (t, string) Result.t
  end
end

module Response_payload : sig
  module type S = sig
    type t

    include Metadatable with type t := t

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

  val to_yojson : t -> Yojson.Safe.t
end

module Make
    (B : Backend.S) : sig
    module B : Backend.S

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
        type _ t

        val empty : unit t

        (** One mebibyte. *)
        val default_max_body_bytes : int

        val json
          :  ?max_body_bytes:int
          -> (module Request_payload.S with type t = 'a)
          -> 'a t

        val text : ?max_body_bytes:int -> description:string -> unit -> string t
      end

      module Response : sig
        type 'a t

        (** Declares the exact JSON wire type returned by the handler. *)
        val json : (module Response_payload.S with type t = 'a) -> 'a t

        val text : description:string -> unit -> string t
        val json_raw : description:string -> unit -> Yojson.Safe.t t
        val empty : description:string -> unit -> unit t
      end

      module Context : sig
        type 'a t

        (** The backend request as handler context. This is used by [make]. *)
        val request : B.req t

        val map : 'a t -> f:('a -> 'b) -> 'b t

        (** Resolves contexts from left to right and stops at the first rejection. *)
        val both : 'a t -> 'b t -> ('a * 'b) t
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
      end

      module Decode_error_response : sig
        type t

        (** Defines one typed JSON shape for path, query, media-type, size, and
            body decode failures. Runtime selects the fixed 400, 413, or 415
            status and OpenAPI declares every status reachable by the endpoint. *)
        val json
          :  payload:(module Response_payload.S with type t = 'a)
          -> map:(Decode_error.t -> 'a)
          -> t
      end

      type (_, _) path

      val nil : ('f, 'f) path
      val s : string -> ('h, 'f) path -> ('h, 'f) path

      val param
        :  string
        -> (module Param.S with type t = 'p)
        -> ('h, 'f) path
        -> ('p -> 'h, 'f) path

      val query
        :  string
        -> (module Query.S with type t = 'q)
        -> ('h, 'f) path
        -> ('q option -> 'h, 'f) path

      val query_req
        :  string
        -> (module Query.S with type t = 'q)
        -> ('h, 'f) path
        -> ('q -> 'h, 'f) path

      val ( / ) : ('a -> 'b) -> ('c -> 'a) -> 'c -> 'b
      val ( /? ) : ('a -> 'b) -> 'a -> 'b

      type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) responses =
        (never, never, never, never, never, never, never, never, never) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      val ( |+ )
        :  (('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h, 'i) rb
            -> ('j, 'k, 'l, 'm, 'n, 'o, 'p, 'q, 'r) rb)
        -> (('s, 't, 'u, 'v, 'w, 'x, 'y, 'z, 'a1) rb
            -> ('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h, 'i) rb)
        -> ('s, 't, 'u, 'v, 'w, 'x, 'y, 'z, 'a1) rb
        -> ('j, 'k, 'l, 'm, 'n, 'o, 'p, 'q, 'r) rb

      module JSON : sig
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
      end

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

      val code4xx
        :  B.client_error_status list
        -> 'code4xx Response.t
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, never, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      val code5xx
        :  B.server_error_status list
        -> 'code5xx Response.t
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, never, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      val code
        :  B.status_code list
        -> 'code Response.t
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, never) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      val ok
        :  'ok Response.t
        -> (never, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      val created
        :  'created Response.t
        -> ('ok, never, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      val not_found
        :  'nf Response.t
        -> ('ok, 'created, 'code2xx, never, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      val bad_request
        :  'bad Response.t
        -> ('ok, 'created, 'code2xx, 'nf, never, 'code4xx, 'ise, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      val internal_server_error
        :  'ise Response.t
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, never, 'code5xx, 'code) rb
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

      module Route : sig
        type t
      end

      (** Resolves [context] before path, query, and body decoding. A context
          rejection short-circuits the endpoint with its declared response. *)
      val make_with
        :  context:'context Context.t
        -> meth:B.meth
        -> ?summary:string
        -> ?tags:string list
        -> ?deprecated:bool
        -> ?operation_id:string
        -> ?description:string
        -> ?decode_error:Decode_error_response.t
        -> request:'req Request.t
        -> path:
             ( 'h
               , 'context
                 -> 'req
                 -> ( 'ok
                      , 'created
                      , 'code2xx
                      , 'nf
                      , 'bad
                      , 'code4xx
                      , 'ise
                      , 'code5xx
                      , 'code )
                      resp
                      B.io )
               path
        -> responses:
             ( 'ok
               , 'created
               , 'code2xx
               , 'nf
               , 'bad
               , 'code4xx
               , 'ise
               , 'code5xx
               , 'code )
               responses
        -> 'h
        -> Route.t

      val make
        :  meth:B.meth
        -> ?summary:string
        -> ?tags:string list
        -> ?deprecated:bool
        -> ?operation_id:string
        -> ?description:string
        -> ?decode_error:Decode_error_response.t
        -> request:'req Request.t
        -> path:
             ( 'h
               , B.req
                 -> 'req
                 -> ( 'ok
                      , 'created
                      , 'code2xx
                      , 'nf
                      , 'bad
                      , 'code4xx
                      , 'ise
                      , 'code5xx
                      , 'code )
                      resp
                      B.io )
               path
        -> responses:
             ( 'ok
               , 'created
               , 'code2xx
               , 'nf
               , 'bad
               , 'code4xx
               , 'ise
               , 'code5xx
               , 'code )
               responses
        -> 'h
        -> Route.t

      module Group : sig
        type t

        (** [decode_error] overrides the application policy for every fallible route
            in the group unless the endpoint has its own override. *)
        val v
          :  ?prefix:string list
          -> ?decode_error:Decode_error_response.t
          -> metadata:Operation_metadata.t
          -> Route.t list
          -> t
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
        type t =
          | Duplicate_route of
              { meth : string
              ; path : string
              }
          | Duplicate_operation_id of string
          | Duplicate_response_status of
              { meth : string
              ; path : string
              ; status : int
              }
          | Empty_response_family of
              { meth : string
              ; path : string
              }
          | Invalid_no_content_response of
              { meth : string
              ; path : string
              }
          | Missing_decode_error_policy of
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
          take precedence over [decode_error]. *)
      val compile
        :  ?decode_error:Decode_error_response.t
        -> Group.t list
        -> (Compiled.t, Compile_error.t list) Result.t

      (** Like [compile], but raises [Failure] with all validation errors. *)
      val compile_exn
        :  ?decode_error:Decode_error_response.t
        -> Group.t list
        -> Compiled.t
    end
  end
  with module B = B
