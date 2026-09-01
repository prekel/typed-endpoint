open! Base

module Json_schema = struct
  type t = Yojson.Safe.t
end

module Metadata = struct
  type t =
    { description : string
    ; summary : string option
    ; tags : string list
    ; deprecated : bool
    ; operation_id : string option
    }

  let v ?summary ?(tags = []) ?(deprecated = false) ?operation_id ~description () =
    { description; summary; tags; deprecated; operation_id }
  ;;
end

module type Json_schemable = sig
  type t

  val t_jsonschema : Json_schema.t
end

module type Metadatable = sig
  type t

  val metadata : Metadata.t
end

module Backend = struct
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

module Param = struct
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t

    include Json_schemable with type t := t
    include Metadatable with type t := t
  end
end

module Query = struct
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t

    include Json_schemable with type t := t
    include Metadatable with type t := t
  end
end

module Request_payload = struct
  module type S = sig
    type t

    include Json_schemable with type t := t
    include Metadatable with type t := t

    val of_yojson : Yojson.Safe.t -> (t, string) Result.t
  end
end

module Response_payload = struct
  module type S = sig
    type t

    include Json_schemable with type t := t
    include Metadatable with type t := t

    val to_yojson : t -> Yojson.Safe.t
  end
end

module Parse_error = struct
  type t =
    { param : string
    ; value : string
    ; error : string
    }
  [@@deriving yojson, jsonschema]

  let v ~param ~value ~error = { param; value; error }
  let of_param_error param value error = v ~param ~value ~error
  let of_query_error param value error = v ~param ~value ~error
  let of_body_error param json error = v ~param ~value:(Yojson.Safe.to_string json) ~error
  let metadata = Metadata.v ~description:"Parse error" ~tags:[ "errors" ] ()
end

module Wrapper = struct
  module Wrapped = struct
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

  module Identity : S1 = struct
    module Wrap_ok (Inner : Response_payload.S) = struct
      include Inner
      module Inner = Inner

      let wrap x = x
    end

    module Wrap_error (Inner : Response_payload.S) = struct
      include Inner
      module Inner = Inner

      let wrap x = x
    end

    module Wrap_parse_error (Inner : Response_payload.S with type t = Parse_error.t) =
    struct
      include Inner
      module Inner = Inner

      let wrap x = x
    end
  end
end

module Make (B : Backend.S) (W : Wrapper.S1) = struct
  module B = B

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

  module D = struct
    type never = |

    module Request = struct
      type _ t =
        | Empty : unit t
        | JSON : (module Request_payload.S with type t = 'a) -> 'a t
        | PlainText : { metadata : Metadata.t } -> string t

      let empty = Empty

      let json (type a) (module R : Request_payload.S with type t = a) : a t =
        JSON (module R)
      ;;

      let text ~description : string t =
        PlainText { metadata = Metadata.v ~description () }
      ;;
    end

    module Response = struct
      type _ payload =
        | JsonWrapped :
            (module Response_payload.S with type t = 'a)
            * (module Wrapper.Wrapped.S with type Inner.t = 'a and type t = 'b)
            -> 'a payload
        | Json : (module Response_payload.S with type t = 'a) -> 'a payload
        | JsonRaw : Yojson.Safe.t payload
        | PlainText : string payload
        | Empty : unit payload

      type 'a t =
        { payload : 'a payload
        ; metadata : Metadata.t
        }

      let json_ok : type a. (module Response_payload.S with type t = a) -> a t =
        fun (module P : Response_payload.S with type t = a) ->
        { payload = JsonWrapped ((module P), (module W.Wrap_ok (P)))
        ; metadata = P.metadata
        }
      ;;

      let json_error : type a. (module Response_payload.S with type t = a) -> a t =
        fun (module P : Response_payload.S with type t = a) ->
        { payload = JsonWrapped ((module P), (module W.Wrap_error (P)))
        ; metadata = P.metadata
        }
      ;;

      let json_ : type a. (module Response_payload.S with type t = a) -> a t =
        fun (module P : Response_payload.S with type t = a) ->
        { payload = Json (module P); metadata = P.metadata }
      ;;

      let json_custom
        : type a.
          (module Response_payload.S with type t = a)
          -> (module Wrapper.Wrapped.S with type Inner.t = a)
          -> a t
        =
        fun (module P : Response_payload.S with type t = a)
          (module F : Wrapper.Wrapped.S with type Inner.t = a) ->
        { payload = JsonWrapped ((module P), (module F)); metadata = P.metadata }
      ;;

      let text ~description () : string t =
        { payload = PlainText; metadata = Metadata.v ~description () }
      ;;

      let json_raw ~description () : Yojson.Safe.t t =
        { payload = JsonRaw; metadata = Metadata.v ~description () }
      ;;

      let empty ~description () : unit t =
        { payload = Empty; metadata = Metadata.v ~description () }
      ;;
    end

    type (_, _) path =
      | End : ('f, 'f) path
      | Static : string * ('h, 'f) path -> ('h, 'f) path
      | Param :
          string * (module Param.S with type t = 'p) * ('h, 'f) path
          -> ('p -> 'h, 'f) path
      | Query :
          string * (module Query.S with type t = 'q) * ('h, 'f) path
          -> ('q option -> 'h, 'f) path
      | QueryReq :
          string * (module Query.S with type t = 'q) * ('h, 'f) path
          -> ('q -> 'h, 'f) path

    let nil : ('f, 'f) path = End
    let s seg tail = Static (seg, tail)

    let param
          (type p h f)
          name
          ((module P : Param.S with type t = p) as pm)
          (tail : (h, f) path)
      : (p -> h, f) path
      =
      Param (name, pm, tail)
    ;;

    let query
          (type q h f)
          name
          ((module Q : Query.S with type t = q) as qm)
          (tail : (h, f) path)
      : (q option -> h, f) path
      =
      Query (name, qm, tail)
    ;;

    let query_req
          (type q h f)
          name
          ((module Q : Query.S with type t = q) as qm)
          (tail : (h, f) path)
      : (q -> h, f) path
      =
      QueryReq (name, qm, tail)
    ;;

    let ( / ) m1 m2 r = m1 (m2 r)
    let ( /? ) m1 r = m1 r

    let path_to_string : type h f. (h, f) path -> string =
      fun p ->
      let rec collect : type h f. (h, f) path -> string list -> string list =
        fun p acc ->
        match p with
        | End -> acc
        | Static (seg, rest) -> collect rest (seg :: acc)
        | Param (name, (module P : Param.S with type t = _), rest) ->
          collect rest ((":" ^ name) :: acc)
        | Query (_, _, rest) -> collect rest acc
        | QueryReq (_, _, rest) -> collect rest acc
      in
      let segments = List.rev (collect p []) in
      match segments with
      | [] -> "/"
      | _ -> "/" ^ String.concat ~sep:"/" segments
    ;;

    let metadata_of_opts ?summary ?tags ?deprecated ?operation_id ?description ()
      : Metadata.t option
      =
      match description, summary, tags, deprecated, operation_id with
      | None, None, None, None, None -> None
      | _ ->
        let description = Option.value description ~default:"" in
        let tags = Option.value tags ~default:[] in
        let deprecated = Option.value deprecated ~default:false in
        Some (Metadata.v ?summary ~tags ~deprecated ?operation_id ~description ())
    ;;

    module WrappedParseError = W.Wrap_parse_error (Parse_error)

    let render_parse_error (pe : Parse_error.t) : B.resp Lwt.t =
      let wrapped = WrappedParseError.wrap pe in
      B.respond_json ~status:`Bad_request (WrappedParseError.to_yojson wrapped)
    ;;

    let rec apply_path : type h f. (h, f) path -> h -> B.req -> (f, B.resp Lwt.t) Result.t
      =
      fun pattern handler req0 ->
      match pattern with
      | End -> Ok handler
      | Static (_seg, rest) -> apply_path rest handler req0
      | Param (name, (module P : Param.S with type t = _), rest) ->
        let raw = B.param req0 name in
        (match P.of_string raw with
         | Error e -> Error (render_parse_error (Parse_error.of_param_error name raw e))
         | Ok v ->
           let handler' = handler v in
           apply_path rest handler' req0)
      | Query (name, (module Q : Query.S with type t = _), rest) ->
        let raw_opt = B.query req0 name in
        let parsed =
          match raw_opt with
          | None -> Ok None
          | Some s -> Result.map (Q.of_string s) ~f:Option.some
        in
        (match parsed with
         | Error e ->
           Error
             (render_parse_error
                (Parse_error.of_query_error name (Option.value raw_opt ~default:"") e))
         | Ok v_opt ->
           let handler' = handler v_opt in
           apply_path rest handler' req0)
      | QueryReq (name, (module Q : Query.S with type t = _), rest) ->
        let raw_opt = B.query req0 name in
        let parsed =
          match raw_opt with
          | None -> Error "No param"
          | Some s -> Q.of_string s
        in
        (match parsed with
         | Error e ->
           Error
             (render_parse_error
                (Parse_error.of_query_error name (Option.value raw_opt ~default:"") e))
         | Ok v_opt ->
           let handler' = handler v_opt in
           apply_path rest handler' req0)
    ;;

    let parse_request
      : type req. req Request.t -> B.req -> (req, B.resp Lwt.t) Result.t Lwt.t
      =
      fun spec req0 ->
      match spec with
      | Request.Empty -> Lwt.return (Ok ())
      | Request.PlainText _ ->
        let%lwt s = B.body_to_string req0 in
        Lwt.return (Ok s)
      | Request.JSON (module Rq) ->
        let%lwt s = B.body_to_string req0 in
        let json =
          try Ok (Yojson.Safe.from_string s) with
          | _ -> Error (Parse_error.of_body_error "body" (`String s) "invalid json")
        in
        (match json with
         | Error pe -> Lwt.return (Error (render_parse_error pe))
         | Ok json ->
           (match Rq.of_yojson json with
            | Ok v -> Lwt.return (Ok v)
            | Error err ->
              Lwt.return
                (Error (render_parse_error (Parse_error.of_body_error "body" json err)))))
    ;;

    let respond_ok_with_status
      : type a. status:B.status_code -> a Response.t -> a -> B.resp Lwt.t
      =
      fun ~status spec v ->
      match spec.payload with
      | Response.Empty -> B.respond_string ~status ""
      | Response.PlainText -> B.respond_string ~status v
      | Response.JsonRaw -> B.respond_json ~status v
      | JsonWrapped ((module _), (module F)) ->
        let out = F.wrap v in
        B.respond_json ~status (F.to_yojson out)
      | Response.Json (module P) -> B.respond_json ~status (P.to_yojson v)
    ;;

    type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb =
      | RNil : (never, never, never, never, never, never, never, never, never) rb
      | R_OK :
          'ok Response.t
          * (never, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      | R_Created :
          'created Response.t
          * ('ok, never, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      | R_Code2xx :
          B.success_status list
          * 'code2xx Response.t
          * ('ok, 'created, never, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      | R_Not_found :
          'nf Response.t
          * ('ok, 'created, 'code2xx, never, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      | R_Bad_request :
          'bad Response.t
          * ('ok, 'created, 'code2xx, 'nf, never, 'code4xx, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      | R_Code4xx :
          B.client_error_status list
          * 'code4xx Response.t
          * ('ok, 'created, 'code2xx, 'nf, 'bad, never, 'ise, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      | R_Internal_server_error :
          'ise Response.t
          * ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, never, 'code5xx, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      | R_Code5xx :
          B.server_error_status list
          * 'code5xx Response.t
          * ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, never, 'code) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      | R_Code :
          B.status_code list
          * 'code Response.t
          * ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, never) rb
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

    let ok (spec : 'ok Response.t)
      :  (never, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      =
      fun tail -> R_OK (spec, tail)
    ;;

    let created (spec : 'c Response.t)
      :  ('ok, never, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      -> ('ok, 'c, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      =
      fun tail -> R_Created (spec, tail)
    ;;

    let code2xx (codes : B.success_status list) (spec : 'c2 Response.t)
      :  ('ok, 'created, never, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      -> ('ok, 'created, 'c2, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      =
      fun tail -> R_Code2xx (codes, spec, tail)
    ;;

    let not_found (spec : 'nf Response.t)
      :  ('ok, 'created, 'code2xx, never, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      =
      fun tail -> R_Not_found (spec, tail)
    ;;

    let bad_request (spec : 'bad Response.t)
      :  ('ok, 'created, 'code2xx, 'nf, never, 'code4xx, 'ise, 'code5xx, 'code) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      =
      fun tail -> R_Bad_request (spec, tail)
    ;;

    let code4xx (codes : B.client_error_status list) (spec : 'c4 Response.t)
      :  ('ok, 'created, 'code2xx, 'nf, 'bad, never, 'ise, 'code5xx, 'code) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'c4, 'ise, 'code5xx, 'code) rb
      =
      fun tail -> R_Code4xx (codes, spec, tail)
    ;;

    let internal_server_error (spec : 'ise Response.t)
      :  ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, never, 'code5xx, 'code) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      =
      fun tail -> R_Internal_server_error (spec, tail)
    ;;

    let code5xx (codes : B.server_error_status list) (spec : 'c5 Response.t)
      :  ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, never, 'code) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'c5, 'code) rb
      =
      fun tail -> R_Code5xx (codes, spec, tail)
    ;;

    let code (codes : B.status_code list) (spec : 'code Response.t)
      :  ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, never) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      =
      fun tail -> R_Code (codes, spec, tail)
    ;;

    let ( |+ ) f g x = f (g x)

    module JSON = struct
      let ok m = ok (Response.json_ok m)
      let created m = created (Response.json_ok m)
      let bad_request m = bad_request (Response.json_error m)
      let not_found m = not_found (Response.json_error m)
      let internal_server_error m = internal_server_error (Response.json_error m)
    end

    let rec get_ok
      : type ok created c2 nf bad c4 ise c5 code.
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> ok Response.t
      = function
      | R_OK (spec, _) -> spec
      | R_Created (_, tl) -> get_ok tl
      | R_Code2xx (_, _, tl) -> get_ok tl
      | R_Not_found (_, tl) -> get_ok tl
      | R_Bad_request (_, tl) -> get_ok tl
      | R_Code4xx (_, _, tl) -> get_ok tl
      | R_Internal_server_error (_, tl) -> get_ok tl
      | R_Code5xx (_, _, tl) -> get_ok tl
      | R_Code (_, _, tl) -> get_ok tl
      | RNil -> failwith "OK response not configured"
    ;;

    let rec get_created
      : type ok created c2 nf bad c4 ise c5 code.
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> created Response.t
      = function
      | R_Created (spec, _) -> spec
      | R_OK (_, tl) -> get_created tl
      | R_Code2xx (_, _, tl) -> get_created tl
      | R_Not_found (_, tl) -> get_created tl
      | R_Bad_request (_, tl) -> get_created tl
      | R_Code4xx (_, _, tl) -> get_created tl
      | R_Internal_server_error (_, tl) -> get_created tl
      | R_Code5xx (_, _, tl) -> get_created tl
      | R_Code (_, _, tl) -> get_created tl
      | RNil -> failwith "Created response not configured"
    ;;

    let rec get_not_found
      : type ok created c2 nf bad c4 ise c5 code.
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> nf Response.t
      = function
      | R_Not_found (spec, _) -> spec
      | R_OK (_, tl) -> get_not_found tl
      | R_Created (_, tl) -> get_not_found tl
      | R_Code2xx (_, _, tl) -> get_not_found tl
      | R_Bad_request (_, tl) -> get_not_found tl
      | R_Code4xx (_, _, tl) -> get_not_found tl
      | R_Internal_server_error (_, tl) -> get_not_found tl
      | R_Code5xx (_, _, tl) -> get_not_found tl
      | R_Code (_, _, tl) -> get_not_found tl
      | RNil -> failwith "Not_found response not configured"
    ;;

    let rec get_bad_request
      : type ok created c2 nf bad c4 ise c5 code.
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> bad Response.t
      = function
      | R_Bad_request (spec, _) -> spec
      | R_OK (_, tl) -> get_bad_request tl
      | R_Created (_, tl) -> get_bad_request tl
      | R_Code2xx (_, _, tl) -> get_bad_request tl
      | R_Not_found (_, tl) -> get_bad_request tl
      | R_Code4xx (_, _, tl) -> get_bad_request tl
      | R_Internal_server_error (_, tl) -> get_bad_request tl
      | R_Code5xx (_, _, tl) -> get_bad_request tl
      | R_Code (_, _, tl) -> get_bad_request tl
      | RNil -> failwith "Bad_request response not configured"
    ;;

    let rec get_internal_server_error
      : type ok created c2 nf bad c4 ise c5 code.
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> ise Response.t
      = function
      | R_Internal_server_error (spec, _) -> spec
      | R_OK (_, tl) -> get_internal_server_error tl
      | R_Created (_, tl) -> get_internal_server_error tl
      | R_Code2xx (_, _, tl) -> get_internal_server_error tl
      | R_Not_found (_, tl) -> get_internal_server_error tl
      | R_Bad_request (_, tl) -> get_internal_server_error tl
      | R_Code4xx (_, _, tl) -> get_internal_server_error tl
      | R_Code5xx (_, _, tl) -> get_internal_server_error tl
      | R_Code (_, _, tl) -> get_internal_server_error tl
      | RNil -> failwith "Internal_server_error response not configured"
    ;;

    let rec get_code2xx_any
      : type ok created c2 nf bad c4 ise c5 code.
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> c2 Response.t
      = function
      | R_Code2xx (_codes, spec, _) -> spec
      | R_OK (_, tl) -> get_code2xx_any tl
      | R_Created (_, tl) -> get_code2xx_any tl
      | R_Not_found (_, tl) -> get_code2xx_any tl
      | R_Bad_request (_, tl) -> get_code2xx_any tl
      | R_Code4xx (_, _, tl) -> get_code2xx_any tl
      | R_Internal_server_error (_, tl) -> get_code2xx_any tl
      | R_Code5xx (_, _, tl) -> get_code2xx_any tl
      | R_Code (_, _, tl) -> get_code2xx_any tl
      | RNil -> failwith "Code_2xx response not configured"
    ;;

    let rec get_code4xx_any
      : type ok created c2 nf bad c4 ise c5 code.
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> c4 Response.t
      = function
      | R_Code4xx (_codes, spec, _) -> spec
      | R_OK (_, tl) -> get_code4xx_any tl
      | R_Created (_, tl) -> get_code4xx_any tl
      | R_Code2xx (_, _, tl) -> get_code4xx_any tl
      | R_Not_found (_, tl) -> get_code4xx_any tl
      | R_Bad_request (_, tl) -> get_code4xx_any tl
      | R_Internal_server_error (_, tl) -> get_code4xx_any tl
      | R_Code5xx (_, _, tl) -> get_code4xx_any tl
      | R_Code (_, _, tl) -> get_code4xx_any tl
      | RNil -> failwith "Code_4xx response not configured"
    ;;

    let rec get_code5xx_any
      : type ok created c2 nf bad c4 ise c5 code.
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> c5 Response.t
      = function
      | R_Code5xx (_codes, spec, _) -> spec
      | R_OK (_, tl) -> get_code5xx_any tl
      | R_Created (_, tl) -> get_code5xx_any tl
      | R_Code2xx (_, _, tl) -> get_code5xx_any tl
      | R_Not_found (_, tl) -> get_code5xx_any tl
      | R_Bad_request (_, tl) -> get_code5xx_any tl
      | R_Code4xx (_, _, tl) -> get_code5xx_any tl
      | R_Internal_server_error (_, tl) -> get_code5xx_any tl
      | R_Code (_, _, tl) -> get_code5xx_any tl
      | RNil -> failwith "Code_5xx response not configured"
    ;;

    let rec get_code_any
      : type ok created c2 nf bad c4 ise c5 code.
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> code Response.t
      = function
      | R_Code (_codes, spec, _) -> spec
      | R_OK (_, tl) -> get_code_any tl
      | R_Created (_, tl) -> get_code_any tl
      | R_Code2xx (_, _, tl) -> get_code_any tl
      | R_Not_found (_, tl) -> get_code_any tl
      | R_Bad_request (_, tl) -> get_code_any tl
      | R_Code4xx (_, _, tl) -> get_code_any tl
      | R_Internal_server_error (_, tl) -> get_code_any tl
      | R_Code5xx (_, _, tl) -> get_code_any tl
      | RNil -> failwith "Code response not configured"
    ;;

    type ('h
         , 'req
         , 'ok
         , 'created
         , 'code2xx
         , 'nf
         , 'bad
         , 'code4xx
         , 'ise
         , 'code5xx
         , 'code)
         builder =
      { meth : B.meth
      ; pattern :
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
      ; request : 'req Request.t
      ; responses :
          ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      ; metadata : Metadata.t option
      }

    type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) responses =
      (never, never, never, never, never, never, never, never, never) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

    let mk
          (type h req ok created code2xx nf bad code4xx ise code5xx code)
          (meth : B.meth)
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ~(request : req Request.t)
          ~(path :
             ( h
               , B.req
                 -> req
                 -> (ok, created, code2xx, nf, bad, code4xx, ise, code5xx, code) resp
                      Lwt.t )
               path)
          ~(responses :
             (ok, created, code2xx, nf, bad, code4xx, ise, code5xx, code) responses)
          ()
      : (h, req, ok, created, code2xx, nf, bad, code4xx, ise, code5xx, code) builder
      =
      { meth
      ; pattern = path
      ; request
      ; responses = responses RNil
      ; metadata =
          metadata_of_opts ?summary ?tags ?deprecated ?operation_id ?description ()
      }
    ;;

    let render_resp
          (b :
            ( _
              , _
              , 'ok
              , 'created
              , 'code2xx
              , 'nf
              , 'bad
              , 'code4xx
              , 'ise
              , 'code5xx
              , 'code )
              builder)
          (r : ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp)
      : B.resp Lwt.t
      =
      match r with
      | OK v ->
        let spec = get_ok b.responses in
        respond_ok_with_status ~status:`OK spec v
      | Created v ->
        let spec = get_created b.responses in
        respond_ok_with_status ~status:`Created spec v
      | Code_2xx (st, v) ->
        let spec = get_code2xx_any b.responses in
        respond_ok_with_status ~status:((st :> B.status) :> B.status_code) spec v
      | Not_found v ->
        let spec = get_not_found b.responses in
        respond_ok_with_status ~status:`Not_found spec v
      | Bad_request v ->
        let spec = get_bad_request b.responses in
        respond_ok_with_status ~status:`Bad_request spec v
      | Code_4xx (st, v) ->
        let spec = get_code4xx_any b.responses in
        respond_ok_with_status ~status:((st :> B.status) :> B.status_code) spec v
      | Internal_server_error v ->
        let spec = get_internal_server_error b.responses in
        respond_ok_with_status ~status:`Internal_server_error spec v
      | Code_5xx (st, v) ->
        let spec = get_code5xx_any b.responses in
        respond_ok_with_status ~status:((st :> B.status) :> B.status_code) spec v
      | Code (st, v) ->
        let spec = get_code_any b.responses in
        respond_ok_with_status ~status:st spec v
      | Raw resp -> Lwt.return resp
    ;;

    module Openapi = struct
      type http_meth = B.meth

      type param_kind =
        [ `Path
        | `Query
        ]

      type param_spec =
        { name : string
        ; kind : param_kind
        ; required : bool
        ; schema : Json_schema.t
        ; meta : Metadata.t
        }

      type request_body_spec =
        | No_body
        | Json_body of
            { schema : Json_schema.t
            ; meta : Metadata.t
            }
        | Text_body of { meta : Metadata.t }

      type response_payload_spec =
        | Resp_empty of { meta : Metadata.t }
        | Resp_text of { meta : Metadata.t }
        | Resp_json of
            { schema : Json_schema.t
            ; meta : Metadata.t
            }

      type response_spec =
        { status : B.status_code
        ; payload : response_payload_spec
        }

      type endpoint =
        { meth : http_meth
        ; path : string
        ; operation_meta : Metadata.t option
        ; params : param_spec list
        ; request_body : request_body_spec
        ; responses : response_spec list
        }

      let path_to_openapi (path : string) : string =
        let segs =
          String.split ~on:'/' path
          |> List.map ~f:(fun seg ->
            if String.is_prefix seg ~prefix:":" then
              "{" ^ String.drop_prefix seg 1 ^ "}"
            else
              seg)
        in
        String.concat ~sep:"/" segs
      ;;

      let prefix_to_string (segs : string list) : string =
        match segs with
        | [] -> ""
        | _ -> "/" ^ String.concat ~sep:"/" segs
      ;;

      let meth_to_string : http_meth -> string = function
        | `GET -> "get"
        | `POST -> "post"
        | `HEAD -> "head"
        | `DELETE -> "delete"
        | `PATCH -> "patch"
        | `PUT -> "put"
        | `OPTIONS -> "options"
        | `TRACE -> "trace"
        | `CONNECT -> "connect"
        | `Other o -> String.lowercase o
      ;;

      let status_code_to_int = B.code_of_status

      let request_body_spec_of_request : type req. req Request.t -> request_body_spec =
        fun r ->
        match r with
        | Request.Empty -> No_body
        | Request.PlainText { metadata } -> Text_body { meta = metadata }
        | Request.JSON (module Rq) ->
          Json_body { schema = Rq.t_jsonschema; meta = Rq.metadata }
      ;;

      let response_payload_spec_of_response
        : type a. a Response.t -> response_payload_spec
        =
        fun r ->
        match r.payload with
        | Response.Empty -> Resp_empty { meta = r.metadata }
        | Response.PlainText -> Resp_text { meta = r.metadata }
        | Response.JsonRaw -> Resp_text { meta = r.metadata }
        | Response.Json (module P) ->
          Resp_json { schema = P.t_jsonschema; meta = r.metadata }
        | Response.JsonWrapped
            ((_ : (module Response_payload.S with type t = a)), (module F)) ->
          Resp_json { schema = F.t_jsonschema; meta = r.metadata }
      ;;

      let rec path_params : type h f. (h, f) path -> param_spec list =
        fun p ->
        match p with
        | End -> []
        | Static (_, rest) -> path_params rest
        | Param (name, (module P : Param.S with type t = _), rest) ->
          { name
          ; kind = `Path
          ; required = true
          ; schema = P.t_jsonschema
          ; meta = P.metadata
          }
          :: path_params rest
        | Query (name, (module Q : Query.S with type t = _), rest) ->
          { name
          ; kind = `Query
          ; required = false
          ; schema = Q.t_jsonschema
          ; meta = Q.metadata
          }
          :: path_params rest
        | QueryReq (name, (module Q : Query.S with type t = _), rest) ->
          { name
          ; kind = `Query
          ; required = true
          ; schema = Q.t_jsonschema
          ; meta = Q.metadata
          }
          :: path_params rest
      ;;

      let rec collect_responses
        : type ok created c2 nf bad c4 ise c5 code.
          (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> response_spec list
        = function
        | RNil -> []
        | R_OK (spec, tl) ->
          { status = (`OK :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Created (spec, tl) ->
          { status = (`Created :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Code2xx (codes, spec, tl) ->
          List.map codes ~f:(fun st ->
            { status = ((st :> B.status) :> B.status_code)
            ; payload = response_payload_spec_of_response spec
            })
          @ collect_responses tl
        | R_Not_found (spec, tl) ->
          { status = (`Not_found :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Bad_request (spec, tl) ->
          { status = (`Bad_request :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Code4xx (codes, spec, tl) ->
          List.map codes ~f:(fun st ->
            { status = ((st :> B.status) :> B.status_code)
            ; payload = response_payload_spec_of_response spec
            })
          @ collect_responses tl
        | R_Internal_server_error (spec, tl) ->
          { status = (`Internal_server_error :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Code5xx (codes, spec, tl) ->
          List.map codes ~f:(fun st ->
            { status = ((st :> B.status) :> B.status_code)
            ; payload = response_payload_spec_of_response spec
            })
          @ collect_responses tl
        | R_Code (codes, spec, tl) ->
          List.map codes ~f:(fun st ->
            { status = st; payload = response_payload_spec_of_response spec })
          @ collect_responses tl
      ;;

      let yo_str s = `String s
      let yo_bool b = `Bool b
      let yo_list xs = `List xs
      let yo_obj xs = `Assoc xs

      let render_param (p : param_spec) : Yojson.Safe.t =
        yo_obj
          [ "name", yo_str p.name
          ; ( "in"
            , yo_str
                (match p.kind with
                 | `Path -> "path"
                 | `Query -> "query") )
          ; "required", yo_bool p.required
          ; "description", yo_str p.meta.description
          ; "schema", p.schema
          ]
      ;;

      let render_request_body (rb : request_body_spec) : Yojson.Safe.t option =
        match rb with
        | No_body -> None
        | Text_body { meta } ->
          Some
            (yo_obj
               [ "required", yo_bool true
               ; "description", yo_str meta.description
               ; ( "content"
                 , yo_obj
                     [ ( "text/plain"
                       , yo_obj [ "schema", yo_obj [ "type", yo_str "string" ] ] )
                     ] )
               ])
        | Json_body { schema; meta } ->
          Some
            (yo_obj
               [ "required", yo_bool true
               ; "description", yo_str meta.description
               ; "content", yo_obj [ "application/json", yo_obj [ "schema", schema ] ]
               ])
      ;;

      let render_response_payload (p : response_payload_spec) : Yojson.Safe.t =
        match p with
        | Resp_empty { meta } -> yo_obj [ "description", yo_str meta.description ]
        | Resp_text { meta } ->
          yo_obj
            [ "description", yo_str meta.description
            ; ( "content"
              , yo_obj
                  [ "text/plain", yo_obj [ "schema", yo_obj [ "type", yo_str "string" ] ]
                  ] )
            ]
        | Resp_json { schema; meta } ->
          yo_obj
            [ "description", yo_str meta.description
            ; "content", yo_obj [ "application/json", yo_obj [ "schema", schema ] ]
            ]
      ;;

      let merge_operation_meta ~(group : Metadata.t) ~(op : Metadata.t option)
        : Metadata.t option
        =
        match op with
        | None -> Some group
        | Some o ->
          let tags = List.dedup_and_sort ~compare:String.compare (group.tags @ o.tags) in
          Some { o with tags }
      ;;

      let render_operation ~(group_meta : Metadata.t) (ep : endpoint) : Yojson.Safe.t =
        let meta_opt = merge_operation_meta ~group:group_meta ~op:ep.operation_meta in
        let params = yo_list (List.map ep.params ~f:render_param) in
        let request_body = render_request_body ep.request_body in
        let responses =
          ep.responses
          |> List.map ~f:(fun r ->
            Int.to_string (status_code_to_int r.status), render_response_payload r.payload)
          |> yo_obj
        in
        let base = [ "parameters", params; "responses", responses ] in
        let base =
          match request_body with
          | None -> base
          | Some rb -> ("requestBody", rb) :: base
        in
        match meta_opt with
        | None -> yo_obj base
        | Some m ->
          yo_obj
            (List.concat
               [ [ "description", yo_str m.description ]
               ; (match m.summary with
                  | None -> []
                  | Some s -> [ "summary", yo_str s ])
               ; (if List.is_empty m.tags then
                    []
                  else
                    [ "tags", yo_list (List.map m.tags ~f:yo_str) ])
               ; (if m.deprecated then
                    [ "deprecated", yo_bool true ]
                  else
                    [])
               ; (match m.operation_id with
                  | None -> []
                  | Some op_id -> [ "operationId", yo_str op_id ])
               ; base
               ])
      ;;

      type group_rendered =
        { group_meta : Metadata.t
        ; prefix : string list
        ; endpoints : endpoint list
        }

      let render_groups
            ?(title = "API")
            ?(version = "0.1.0")
            (groups : group_rendered list)
        : Yojson.Safe.t
        =
        let tags =
          groups
          |> List.concat_map ~f:(fun g ->
            List.map g.group_meta.tags ~f:(fun name ->
              yo_obj
                [ "name", yo_str name; "description", yo_str g.group_meta.description ]))
          |> fun xs ->
          let tbl = Hashtbl.create (module String) in
          List.iter xs ~f:(function
            | `Assoc kvs as t ->
              (match List.Assoc.find kvs ~equal:String.equal "name" with
               | Some (`String n) ->
                 if not (Hashtbl.mem tbl n) then
                   Hashtbl.set tbl ~key:n ~data:t
               | _ -> ())
            | _ -> ());
          Hashtbl.data tbl |> yo_list
        in
        let by_path = Hashtbl.create (module String) in
        List.iter groups ~f:(fun g ->
          let pref = prefix_to_string g.prefix in
          List.iter g.endpoints ~f:(fun ep ->
            let full_runtime_path =
              if String.is_empty pref then
                ep.path
              else
                pref ^ ep.path
            in
            let path_key = path_to_openapi full_runtime_path in
            let meth_key = meth_to_string ep.meth in
            let op =
              render_operation
                ~group_meta:g.group_meta
                { ep with path = full_runtime_path }
            in
            Hashtbl.update by_path path_key ~f:(function
              | None -> Base.Map.singleton (module String) meth_key op
              | Some m -> Map.set m ~key:meth_key ~data:op)));
        let paths =
          Hashtbl.to_alist by_path
          |> List.map ~f:(fun (p, ops) ->
            let ops_json =
              Map.to_alist ops |> List.map ~f:(fun (k, v) -> k, v) |> yo_obj
            in
            p, ops_json)
          |> yo_obj
        in
        yo_obj
          [ "openapi", yo_str "3.1.0"
          ; "info", yo_obj [ "title", yo_str title; "version", yo_str version ]
          ; "tags", tags
          ; "paths", paths
          ]
      ;;
    end

    module Route = struct
      type t =
        { meth : B.meth
        ; path : string
        ; handler : B.req -> B.resp Lwt.t
        ; endpoint : Openapi.endpoint
        }
    end

    module Group = struct
      type t =
        { prefix : string list
        ; metadata : Metadata.t
        ; routes : Route.t list
        }

      let v ?(prefix = []) ~metadata routes = { prefix; metadata; routes }
    end

    let build_app (groups : Group.t list) : B.app_builder =
      let prefix_to_string = Openapi.prefix_to_string in
      let compile_route ~(prefix : string) (r : Route.t) : B.app_builder =
        let full_path =
          if String.is_empty prefix then
            r.path
          else
            prefix ^ r.path
        in
        B.route r.meth full_path r.handler
      in
      List.fold groups ~init:B.empty ~f:(fun acc g ->
        let prefix = prefix_to_string g.prefix in
        let gb =
          List.fold g.routes ~init:B.empty ~f:(fun acc2 r ->
            B.combine acc2 (compile_route ~prefix r))
        in
        B.combine acc gb)
    ;;

    let openapi (groups : Group.t list) : Yojson.Safe.t =
      let rendered : Openapi.group_rendered list =
        List.map groups ~f:(fun g ->
          { Openapi.group_meta = g.metadata
          ; prefix = g.prefix
          ; endpoints = List.map g.routes ~f:(fun r -> r.endpoint)
          })
      in
      Openapi.render_groups rendered
    ;;

    let make
          ~meth
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ~request
          ~path
          ~responses
          f
      : Route.t
      =
      let b =
        mk
          meth
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ~request
          ~path
          ~responses
          ()
      in
      let path_str = path_to_string b.pattern in
      let wrapped (req0 : B.req) : B.resp Lwt.t =
        match apply_path b.pattern f req0 with
        | Error resp_lwt -> resp_lwt
        | Ok f' ->
          let%lwt parsed = parse_request b.request req0 in
          (match parsed with
           | Error resp_lwt -> resp_lwt
           | Ok body ->
             let%lwt r = f' req0 body in
             render_resp b r)
      in
      let endpoint : Openapi.endpoint =
        { meth = b.meth
        ; path = path_str
        ; operation_meta = b.metadata
        ; params = Openapi.path_params b.pattern
        ; request_body = Openapi.request_body_spec_of_request b.request
        ; responses = Openapi.collect_responses b.responses
        }
      in
      { Route.meth = b.meth; path = path_str; handler = wrapped; endpoint }
    ;;
  end
end
