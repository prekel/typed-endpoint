open! Base

module Metadata : sig
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

module type Json_schemable = sig
  type t

  val t_jsonschema : Yojson.Safe.t
end

module type Metadatable = sig
  type t

  val metadata : Metadata.t
end

module Backend : sig
  module type S = sig
    type req
    type resp

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

    val get : meth
    val post : meth
    val put : meth
    val delete : meth
    val patch : meth
    val route : meth -> string -> (req -> resp Lwt.t) -> app_builder
    val param : req -> string -> string
    val query : req -> string -> string option
    val body_to_string : req -> string Lwt.t
    val respond_string : ?status:status_code -> string -> resp Lwt.t
    val respond_json : ?status:status_code -> Yojson.Safe.t -> resp Lwt.t
    val combine : app_builder -> app_builder -> app_builder
    val empty : app_builder
  end
end

module Param : sig
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t

    include Json_schemable with type t := t
    include Metadatable with type t := t
  end
end

module Query : sig
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t

    include Json_schemable with type t := t
    include Metadatable with type t := t
  end
end

module Request_payload : sig
  module type S = sig
    type t

    include Json_schemable with type t := t
    include Metadatable with type t := t

    val of_yojson : Yojson.Safe.t -> (t, string) Result.t
  end
end

module Response_payload : sig
  module type S = sig
    type t

    include Json_schemable with type t := t
    include Metadatable with type t := t

    val to_yojson : t -> Yojson.Safe.t
  end
end

module Parse_error : sig
  type t =
    { param : string
    ; value : string
    ; error : string
    }

  include Json_schemable with type t := t
  include Metadatable with type t := t

  val to_yojson : t -> Yojson.Safe.t
end

module Wrapper : sig
  module Wrapped : sig
    module type S = sig
      include Response_payload.S
      module Inner : Response_payload.S

      val wrap : Inner.t -> t
    end
  end

  module type S1 = sig
    module Wrap_ok (Inner : Response_payload.S) : Wrapped.S with module Inner = Inner
    module Wrap_error (Inner : Response_payload.S) : Wrapped.S with module Inner = Inner

    module Wrap_parse_error (Inner : Response_payload.S with type t = Parse_error.t) :
      Wrapped.S with module Inner = Inner
  end

  module Identity : S1
end

module Make
    (B : Backend.S)
    (_ : Wrapper.S1) : sig
    module B : Backend.S

    type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp =
      | OK of 'ok
      | Created of 'created
      | Code_2xx of (B.success_status * 'code2xx)
      | Not_found of 'nf
      | Bad_request of 'bad
      | Code_4xx of (B.client_error_status * 'code4xx)
      | Internal_server_error of 'ise
      | Code_5xx of (B.server_error_status * 'code5xx)
      | Code of (B.status_code * 'code)
      | Raw of B.resp

    module D : sig
      type never = |

      module Request : sig
        type _ t

        val empty : unit t
        val json : (module Request_payload.S with type t = 'a) -> 'a t
        val text : description:string -> string t
      end

      module Response : sig
        type 'a t

        val json_ok : (module Response_payload.S with type t = 'a) -> 'a t
        val json_error : (module Response_payload.S with type t = 'a) -> 'a t
        val json_ : (module Response_payload.S with type t = 'a) -> 'a t

        val json_custom
          :  (module Response_payload.S with type t = 'a)
          -> (module Wrapper.Wrapped.S with type Inner.t = 'a)
          -> 'a t

        val text : description:string -> unit -> string t
        val json_raw : description:string -> unit -> Yojson.Safe.t t
        val empty : description:string -> unit -> unit t
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

      val make
        :  meth:B.meth
        -> ?summary:string
        -> ?tags:string list
        -> ?deprecated:bool
        -> ?operation_id:string
        -> ?description:string
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
                      Lwt.t )
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

        val v : ?prefix:string list -> metadata:Metadata.t -> Route.t list -> t
      end

      val build_app : Group.t list -> B.app_builder
      val openapi : Group.t list -> Yojson.Safe.t
    end
  end
  with module B = B
