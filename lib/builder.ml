open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson

module Json_schema = struct
  type t = Ppx_deriving_jsonschema_runtime.t
end

module Metadata = struct
  type 'a t =
    { schema : Json_schema.t
    ; description : string
    ; tags : string list
    }

  let v ~schema ?(tags = []) ~description () = { schema; description; tags }
end

module Operation_metadata = Contract.Operation_metadata
module Documentation = Contract.Documentation

let documentation_of_metadata (type a) (metadata : a Metadata.t) : Documentation.t =
  Documentation.v ~description:metadata.description ~tags:metadata.tags ()
;;

module type Metadatable = sig
  type t

  val metadata : t Metadata.t
end

module Backend = struct
  module type S = sig
    type req
    type resp
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
    val body_to_string : req -> string io
    val respond_string : ?status:status_code -> string -> resp io
    val respond_json : ?status:status_code -> Yojson.Safe.t -> resp io
    val combine : app_builder -> app_builder -> app_builder
    val empty : app_builder
  end
end

module Runtime_error = struct
  type t =
    | Undeclared_status of
        { meth : string
        ; path : string
        ; status : int
        ; declared : int list
        }

  let to_string = function
    | Undeclared_status { meth; path; status; declared } ->
      let declared = declared |> List.map ~f:Int.to_string |> String.concat ~sep:", " in
      "handler returned undeclared status "
      ^ Int.to_string status
      ^ " for "
      ^ meth
      ^ " "
      ^ path
      ^ "; declared: ["
      ^ declared
      ^ "]"
  ;;
end

exception Runtime_error of Runtime_error.t

module Param = struct
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t

    include Metadatable with type t := t
  end
end

module Query = struct
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t

    include Metadatable with type t := t
  end
end

module Request_payload = struct
  module type S = sig
    type t

    include Metadatable with type t := t

    val of_yojson : Yojson.Safe.t -> (t, string) Result.t
  end
end

module Response_payload = struct
  module type S = sig
    type t

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

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Parse error" ~tags:[ "errors" ] ()
  ;;
end

module Make (B : Backend.S) = struct
  module B = B

  let ( let* ) value f = B.bind value ~f
  let ( let+ ) value f = B.bind value ~f:(fun value -> B.return (f value))

  type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp =
    | OK :
        'ok
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
    | Created :
        'created
        -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
    | No_content : ('ok, 'created, unit, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
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

  module D = struct
    type never = |

    module Request = struct
      type _ t =
        | Empty : unit t
        | JSON : (module Request_payload.S with type t = 'a) -> 'a t
        | PlainText : { metadata : Documentation.t } -> string t

      let empty = Empty

      let json (type a) (module R : Request_payload.S with type t = a) : a t =
        JSON (module R)
      ;;

      let text ~description : string t =
        PlainText { metadata = Documentation.v ~description () }
      ;;
    end

    module Response = struct
      type _ payload =
        | Json : (module Response_payload.S with type t = 'a) -> 'a payload
        | JsonRaw : Yojson.Safe.t payload
        | PlainText : string payload
        | Empty : unit payload

      type 'a t =
        { payload : 'a payload
        ; metadata : Documentation.t
        }

      let json : type a. (module Response_payload.S with type t = a) -> a t =
        fun (module P : Response_payload.S with type t = a) ->
        { payload = Json (module P); metadata = documentation_of_metadata P.metadata }
      ;;

      let text ~description () : string t =
        { payload = PlainText; metadata = Documentation.v ~description () }
      ;;

      let json_raw ~description () : Yojson.Safe.t t =
        { payload = JsonRaw; metadata = Documentation.v ~description () }
      ;;

      let empty ~description () : unit t =
        { payload = Empty; metadata = Documentation.v ~description () }
      ;;
    end

    module Context = struct
      type rejection =
        | Rejected :
            { status : B.client_error_status
            ; response : 'error Response.t
            ; error : 'error
            }
            -> rejection

      type declared_response =
        | Declared_response :
            { status : B.client_error_status
            ; response : 'error Response.t
            }
            -> declared_response

      type 'a t =
        { resolve : B.req -> ('a, rejection) Result.t B.io
        ; responses : declared_response list
        }

      let request = { resolve = (fun request -> B.return (Ok request)); responses = [] }

      let map context ~f =
        { context with
          resolve =
            (fun request ->
              let+ result = context.resolve request in
              Result.map result ~f)
        }
      ;;

      let both left right =
        let resolve request =
          let* left_result = left.resolve request in
          match left_result with
          | Error rejection -> B.return (Error rejection)
          | Ok left_value ->
            let+ right_result = right.resolve request in
            Result.map right_result ~f:(fun right_value -> left_value, right_value)
        in
        { resolve; responses = left.responses @ right.responses }
      ;;
    end

    module Dependency = struct
      let value dependency =
        { Context.resolve = (fun _request -> B.return (Ok dependency)); responses = [] }
      ;;

      let of_request resolve =
        { Context.resolve =
            (fun request ->
              let+ dependency = resolve request in
              Ok dependency)
        ; responses = []
        }
      ;;
    end

    module Guard = struct
      let v ~status ~response ~check =
        let resolve request =
          let+ result = check request in
          Result.map_error result ~f:(fun error ->
            Context.Rejected { status; response; error })
        in
        { Context.resolve
        ; responses = [ Context.Declared_response { status; response } ]
        }
      ;;
    end

    module Parse_error_response = struct
      type t =
        | T :
            { status : B.client_error_status
            ; response : 'a Response.t
            ; map : Parse_error.t -> 'a
            }
            -> t

      let json ~status ~payload ~map = T { status; response = Response.json payload; map }
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
      : Operation_metadata.t option
      =
      match description, summary, tags, deprecated, operation_id with
      | None, None, None, None, None -> None
      | _ ->
        let description = Option.value description ~default:"" in
        let tags = Option.value tags ~default:[] in
        let deprecated = Option.value deprecated ~default:false in
        Some
          (Operation_metadata.v ?summary ~tags ~deprecated ?operation_id ~description ())
    ;;

    let meth_to_string : B.meth -> string = function
      | `GET -> "get"
      | `POST -> "post"
      | `HEAD -> "head"
      | `DELETE -> "delete"
      | `PATCH -> "patch"
      | `PUT -> "put"
      | `OPTIONS -> "options"
      | `TRACE -> "trace"
      | `CONNECT -> "connect"
      | `Other method_ -> String.lowercase method_
    ;;

    let rec apply_path
      : type h f. (h, f) path -> h -> B.req -> (f, Parse_error.t) Result.t
      =
      fun pattern handler req0 ->
      match pattern with
      | End -> Ok handler
      | Static (_seg, rest) -> apply_path rest handler req0
      | Param (name, (module P : Param.S with type t = _), rest) ->
        let raw = B.param req0 name in
        (match P.of_string raw with
         | Error e -> Error (Parse_error.of_param_error name raw e)
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
           Error (Parse_error.of_query_error name (Option.value raw_opt ~default:"") e)
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
           Error (Parse_error.of_query_error name (Option.value raw_opt ~default:"") e)
         | Ok v_opt ->
           let handler' = handler v_opt in
           apply_path rest handler' req0)
    ;;

    let parse_request
      : type req. req Request.t -> B.req -> (req, Parse_error.t) Result.t B.io
      =
      fun spec req0 ->
      match spec with
      | Request.Empty -> B.return (Ok ())
      | Request.PlainText _ ->
        let* s = B.body_to_string req0 in
        B.return (Ok s)
      | Request.JSON (module Rq) ->
        let* s = B.body_to_string req0 in
        let json =
          try Ok (Yojson.Safe.from_string s) with
          | Yojson.Json_error _ ->
            Error (Parse_error.of_body_error "body" (`String s) "invalid json")
        in
        (match json with
         | Error pe -> B.return (Error pe)
         | Ok json ->
           (match Rq.of_yojson json with
            | Ok v -> B.return (Ok v)
            | Error err -> B.return (Error (Parse_error.of_body_error "body" json err))))
    ;;

    let respond_ok_with_status
      : type a. status:B.status_code -> a Response.t -> a -> B.resp B.io
      =
      fun ~status spec v ->
      match spec.payload with
      | Response.Empty -> B.respond_string ~status ""
      | Response.PlainText -> B.respond_string ~status v
      | Response.JsonRaw -> B.respond_json ~status v
      | Response.Json (module P) -> B.respond_json ~status (P.to_yojson v)
    ;;

    let render_parse_error_response (Parse_error_response.T policy) error =
      let status = ((policy.status :> B.status) :> B.status_code) in
      respond_ok_with_status ~status policy.response (policy.map error)
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

    let no_content ~description = code2xx [ `No_content ] (Response.empty ~description ())

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
      let ok m = ok (Response.json m)
      let created m = created (Response.json m)
      let bad_request m = bad_request (Response.json m)
      let not_found m = not_found (Response.json m)
      let internal_server_error m = internal_server_error (Response.json m)
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
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb
        -> B.success_status list * c2 Response.t
      = function
      | R_Code2xx (codes, spec, _) -> codes, spec
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
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb
        -> B.client_error_status list * c4 Response.t
      = function
      | R_Code4xx (codes, spec, _) -> codes, spec
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
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb
        -> B.server_error_status list * c5 Response.t
      = function
      | R_Code5xx (codes, spec, _) -> codes, spec
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
        (ok, created, c2, nf, bad, c4, ise, c5, code) rb
        -> B.status_code list * code Response.t
      = function
      | R_Code (codes, spec, _) -> codes, spec
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
         , 'context
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
      ; context : 'context Context.t
      ; request : 'req Request.t
      ; responses :
          ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      ; metadata : Operation_metadata.t option
      ; parse_error : Parse_error_response.t option
      }

    type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) responses =
      (never, never, never, never, never, never, never, never, never) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

    let mk
          (type h context req ok created code2xx nf bad code4xx ise code5xx code)
          (meth : B.meth)
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ?parse_error
          ~(context : context Context.t)
          ~(request : req Request.t)
          ~(path :
             ( h
               , context
                 -> req
                 -> (ok, created, code2xx, nf, bad, code4xx, ise, code5xx, code) resp B.io
               )
               path)
          ~(responses :
             (ok, created, code2xx, nf, bad, code4xx, ise, code5xx, code) responses)
          ()
      : ( h
          , context
          , req
          , ok
          , created
          , code2xx
          , nf
          , bad
          , code4xx
          , ise
          , code5xx
          , code )
          builder
      =
      { meth
      ; pattern = path
      ; context
      ; request
      ; responses = responses RNil
      ; metadata =
          metadata_of_opts ?summary ?tags ?deprecated ?operation_id ?description ()
      ; parse_error
      }
    ;;

    let render_resp
      : type h context req ok created code2xx nf bad code4xx ise code5xx code.
        ( h
          , context
          , req
          , ok
          , created
          , code2xx
          , nf
          , bad
          , code4xx
          , ise
          , code5xx
          , code )
          builder
        -> (ok, created, code2xx, nf, bad, code4xx, ise, code5xx, code) resp
        -> B.resp B.io
      =
      fun b r ->
      let ensure_declared status declared =
        let status = B.code_of_status status in
        let declared = List.map declared ~f:(fun status -> B.code_of_status status) in
        match
          Runtime.ensure_declared
            ~meth:(meth_to_string b.meth)
            ~path:(path_to_string b.pattern)
            ~status
            ~declared
        with
        | Ok () -> ()
        | Error { meth; path; status; declared } ->
          raise (Runtime_error (Undeclared_status { meth; path; status; declared }))
      in
      match r with
      | OK v ->
        let spec = get_ok b.responses in
        respond_ok_with_status ~status:`OK spec v
      | Created v ->
        let spec = get_created b.responses in
        respond_ok_with_status ~status:`Created spec v
      | No_content ->
        let statuses, spec = get_code2xx_any b.responses in
        ensure_declared
          (`No_content :> B.status_code)
          (List.map statuses ~f:(fun status -> ((status :> B.status) :> B.status_code)));
        respond_ok_with_status ~status:`No_content spec ()
      | Code_2xx (st, v) ->
        let statuses, spec = get_code2xx_any b.responses in
        let status = ((st :> B.status) :> B.status_code) in
        ensure_declared
          status
          (List.map statuses ~f:(fun status -> ((status :> B.status) :> B.status_code)));
        respond_ok_with_status ~status spec v
      | Not_found v ->
        let spec = get_not_found b.responses in
        respond_ok_with_status ~status:`Not_found spec v
      | Bad_request v ->
        let spec = get_bad_request b.responses in
        respond_ok_with_status ~status:`Bad_request spec v
      | Code_4xx (st, v) ->
        let statuses, spec = get_code4xx_any b.responses in
        let status = ((st :> B.status) :> B.status_code) in
        ensure_declared
          status
          (List.map statuses ~f:(fun status -> ((status :> B.status) :> B.status_code)));
        respond_ok_with_status ~status spec v
      | Internal_server_error v ->
        let spec = get_internal_server_error b.responses in
        respond_ok_with_status ~status:`Internal_server_error spec v
      | Code_5xx (st, v) ->
        let statuses, spec = get_code5xx_any b.responses in
        let status = ((st :> B.status) :> B.status_code) in
        ensure_declared
          status
          (List.map statuses ~f:(fun status -> ((status :> B.status) :> B.status_code)));
        respond_ok_with_status ~status spec v
      | Code (st, v) ->
        let statuses, spec = get_code_any b.responses in
        ensure_declared st statuses;
        respond_ok_with_status ~status:st spec v
    ;;

    let render_context_rejection (Context.Rejected { status; response; error })
      : B.resp B.io
      =
      let status = ((status :> B.status) :> B.status_code) in
      respond_ok_with_status ~status response error
    ;;

    module Openapi_adapter = struct
      let request_body_spec_of_request : type req. req Request.t -> Contract.request_body =
        fun r ->
        match r with
        | Request.Empty -> Contract.No_body
        | Request.PlainText { metadata } -> Text_body { metadata }
        | Request.JSON (module Rq) ->
          Json_body
            { schema = Rq.metadata.schema
            ; metadata = documentation_of_metadata Rq.metadata
            }
      ;;

      let response_payload_spec_of_response
        : type a. a Response.t -> Contract.response_payload
        =
        fun r ->
        match r.payload with
        | Response.Empty -> { metadata = r.metadata; content = [] }
        | Response.PlainText -> { metadata = r.metadata; content = [ Text ] }
        | Response.JsonRaw -> { metadata = r.metadata; content = [ Json (`Bool true) ] }
        | Response.Json (module P) ->
          { metadata = r.metadata; content = [ Json P.metadata.schema ] }
      ;;

      let response_spec_of_parse_error (Parse_error_response.T policy) =
        { Contract.status =
            B.code_of_status ((policy.status :> B.status) :> B.status_code)
        ; payload = response_payload_spec_of_response policy.response
        }
      ;;

      let response_specs_of_context context =
        List.map context.Context.responses ~f:(fun (Context.Declared_response declared) ->
          { Contract.status =
              B.code_of_status ((declared.status :> B.status) :> B.status_code)
          ; payload = response_payload_spec_of_response declared.response
          })
      ;;

      let rec path_params : type h f. (h, f) path -> Contract.param list =
        fun p ->
        match p with
        | End -> []
        | Static (_, rest) -> path_params rest
        | Param (name, (module P : Param.S with type t = _), rest) ->
          { name
          ; kind = `Path
          ; required = true
          ; schema = P.metadata.schema
          ; metadata = documentation_of_metadata P.metadata
          }
          :: path_params rest
        | Query (name, (module Q : Query.S with type t = _), rest) ->
          { name
          ; kind = `Query
          ; required = false
          ; schema = Q.metadata.schema
          ; metadata = documentation_of_metadata Q.metadata
          }
          :: path_params rest
        | QueryReq (name, (module Q : Query.S with type t = _), rest) ->
          { name
          ; kind = `Query
          ; required = true
          ; schema = Q.metadata.schema
          ; metadata = documentation_of_metadata Q.metadata
          }
          :: path_params rest
      ;;

      let rec collect_responses
        : type ok created c2 nf bad c4 ise c5 code.
          (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> Contract.response list
        = function
        | RNil -> []
        | R_OK (spec, tl) ->
          { Contract.status = B.code_of_status (`OK :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Created (spec, tl) ->
          { Contract.status = B.code_of_status (`Created :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Code2xx (codes, spec, tl) ->
          List.map codes ~f:(fun st ->
            { Contract.status = B.code_of_status ((st :> B.status) :> B.status_code)
            ; payload = response_payload_spec_of_response spec
            })
          @ collect_responses tl
        | R_Not_found (spec, tl) ->
          { Contract.status = B.code_of_status (`Not_found :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Bad_request (spec, tl) ->
          { Contract.status = B.code_of_status (`Bad_request :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Code4xx (codes, spec, tl) ->
          List.map codes ~f:(fun st ->
            { Contract.status = B.code_of_status ((st :> B.status) :> B.status_code)
            ; payload = response_payload_spec_of_response spec
            })
          @ collect_responses tl
        | R_Internal_server_error (spec, tl) ->
          { Contract.status = B.code_of_status (`Internal_server_error :> B.status_code)
          ; payload = response_payload_spec_of_response spec
          }
          :: collect_responses tl
        | R_Code5xx (codes, spec, tl) ->
          List.map codes ~f:(fun st ->
            { Contract.status = B.code_of_status ((st :> B.status) :> B.status_code)
            ; payload = response_payload_spec_of_response spec
            })
          @ collect_responses tl
        | R_Code (codes, spec, tl) ->
          List.map codes ~f:(fun st ->
            { Contract.status = B.code_of_status st
            ; payload = response_payload_spec_of_response spec
            })
          @ collect_responses tl
      ;;

      let rec response_families
        : type ok created c2 nf bad c4 ise c5 code.
          (ok, created, c2, nf, bad, c4, ise, c5, code) rb -> int list list
        = function
        | RNil -> []
        | R_OK (_, tail) ->
          [ B.code_of_status (`OK :> B.status_code) ] :: response_families tail
        | R_Created (_, tail) ->
          [ B.code_of_status (`Created :> B.status_code) ] :: response_families tail
        | R_Code2xx (statuses, _, tail) ->
          List.map statuses ~f:(fun status ->
            B.code_of_status ((status :> B.status) :> B.status_code))
          :: response_families tail
        | R_Not_found (_, tail) ->
          [ B.code_of_status (`Not_found :> B.status_code) ] :: response_families tail
        | R_Bad_request (_, tail) ->
          [ B.code_of_status (`Bad_request :> B.status_code) ] :: response_families tail
        | R_Code4xx (statuses, _, tail) ->
          List.map statuses ~f:(fun status ->
            B.code_of_status ((status :> B.status) :> B.status_code))
          :: response_families tail
        | R_Internal_server_error (_, tail) ->
          [ B.code_of_status (`Internal_server_error :> B.status_code) ]
          :: response_families tail
        | R_Code5xx (statuses, _, tail) ->
          List.map statuses ~f:(fun status ->
            B.code_of_status ((status :> B.status) :> B.status_code))
          :: response_families tail
        | R_Code (statuses, _, tail) ->
          List.map statuses ~f:B.code_of_status :: response_families tail
      ;;

      let rec path_has_parsers : type h f. (h, f) path -> bool = function
        | End -> false
        | Static (_, tail) -> path_has_parsers tail
        | Param _ | Query _ | QueryReq _ -> true
      ;;

      let request_has_parser : type request. request Request.t -> bool = function
        | Request.JSON _ -> true
        | Request.Empty | Request.PlainText _ -> false
      ;;
    end

    module Route = struct
      type t =
        { meth : B.meth
        ; path : string
        ; handler : Parse_error_response.t option -> B.req -> B.resp B.io
        ; contract : Parse_error_response.t option -> Contract.route
        }
    end

    module Unsafe = struct
      let route ~meth ~path ~handler =
        { Route.meth
        ; path
        ; handler = (fun _parse_error -> handler)
        ; contract =
            (fun _parse_error ->
              { Contract.meth = meth_to_string meth; path; endpoint = None })
        }
      ;;
    end

    module Group = struct
      type t =
        { prefix : string list
        ; metadata : Operation_metadata.t
        ; routes : Route.t list
        ; parse_error : Parse_error_response.t option
        }

      let v ?(prefix = []) ?parse_error ~metadata routes =
        { prefix; metadata; routes; parse_error }
      ;;
    end

    let build_app ?parse_error (groups : Group.t list) : B.app_builder =
      let compile_route
            ~(prefix : string)
            ~(parse_error : Parse_error_response.t option)
            (r : Route.t)
        : B.app_builder
        =
        let full_path =
          if String.is_empty prefix then
            r.path
          else
            prefix ^ r.path
        in
        B.route r.meth full_path (r.handler parse_error)
      in
      List.fold groups ~init:B.empty ~f:(fun acc g ->
        let prefix = Contract.prefix_to_string g.prefix in
        let parse_error = Option.first_some g.parse_error parse_error in
        let gb =
          List.fold g.routes ~init:B.empty ~f:(fun acc2 r ->
            B.combine acc2 (compile_route ~prefix ~parse_error r))
        in
        B.combine acc gb)
    ;;

    module Compiled = struct
      type t =
        { contract : Contract.Compiled.t
        ; app : B.app_builder
        }

      let app compiled = compiled.app

      let openapi ?title ?version compiled =
        Openapi.render ?title ?version compiled.contract
      ;;
    end

    module Compile_error = struct
      type t = Contract.Compile_error.t =
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
        | Missing_parse_error_policy of
            { meth : string
            ; path : string
            }

      let to_string = Contract.Compile_error.to_string
    end

    let compile ?parse_error (groups : Group.t list)
      : (Compiled.t, Compile_error.t list) Result.t
      =
      let contract_groups =
        List.map groups ~f:(fun group ->
          let parse_error = Option.first_some group.parse_error parse_error in
          { Contract.prefix = group.prefix
          ; metadata = group.metadata
          ; routes = List.map group.routes ~f:(fun route -> route.contract parse_error)
          })
      in
      Contract.compile contract_groups
      |> Result.map ~f:(fun contract ->
        { Compiled.contract; app = build_app ?parse_error groups })
    ;;

    let compile_exn ?parse_error groups =
      match compile ?parse_error groups with
      | Ok compiled -> compiled
      | Error errors ->
        errors
        |> List.map ~f:Contract.Compile_error.to_string
        |> String.concat ~sep:"; "
        |> failwith
    ;;

    let make_with
          ~context
          ~meth
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ?parse_error
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
          ?parse_error
          ~context
          ~request
          ~path
          ~responses
          ()
      in
      let path_str = path_to_string b.pattern in
      let resolve_parse_error inherited = Option.first_some b.parse_error inherited in
      let render_parse_error inherited error =
        match resolve_parse_error inherited with
        | Some policy -> render_parse_error_response policy error
        | None ->
          failwith
            ("missing parse-error policy for " ^ meth_to_string b.meth ^ " " ^ path_str)
      in
      let wrapped inherited (req0 : B.req) : B.resp B.io =
        let* context_result = b.context.resolve req0 in
        match context_result with
        | Error rejection -> render_context_rejection rejection
        | Ok context ->
          (match apply_path b.pattern f req0 with
           | Error error -> render_parse_error inherited error
           | Ok f' ->
             let* parsed = parse_request b.request req0 in
             (match parsed with
              | Error error -> render_parse_error inherited error
              | Ok body ->
                let* r = f' context body in
                render_resp b r))
      in
      let has_parsers =
        Openapi_adapter.path_has_parsers b.pattern
        || Openapi_adapter.request_has_parser b.request
      in
      let contract inherited =
        let parse_error_response =
          if has_parsers then
            Option.map (resolve_parse_error inherited) ~f:(fun policy ->
              Openapi_adapter.response_spec_of_parse_error policy)
          else
            None
        in
        let endpoint : Contract.endpoint =
          { meth = meth_to_string b.meth
          ; path = path_str
          ; metadata = b.metadata
          ; params = Openapi_adapter.path_params b.pattern
          ; request_body = Openapi_adapter.request_body_spec_of_request b.request
          ; responses = Openapi_adapter.collect_responses b.responses
          ; parse_error_response
          ; context_responses = Openapi_adapter.response_specs_of_context b.context
          ; response_families = Openapi_adapter.response_families b.responses
          ; has_parsers
          }
        in
        { Contract.meth = meth_to_string b.meth
        ; path = path_str
        ; endpoint = Some endpoint
        }
      in
      { Route.meth = b.meth; path = path_str; handler = wrapped; contract }
    ;;

    let make
          ~meth
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ?parse_error
          ~request
          ~path
          ~responses
          f
      =
      make_with
        ~context:Context.request
        ~meth
        ?summary
        ?tags
        ?deprecated
        ?operation_id
        ?description
        ?parse_error
        ~request
        ~path
        ~responses
        f
    ;;
  end
end
