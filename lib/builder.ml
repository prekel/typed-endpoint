open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson

module Json_schema = struct
  type t = Ppx_deriving_jsonschema_runtime.t
end

module Metadata = struct
  type 'a t =
    { schema : Json_schema.t
    ; schema_name : string option
    ; description : string
    ; tags : string list
    }

  let v ~schema ?schema_name ?(tags = []) ~description () =
    { schema; schema_name; description; tags }
  ;;
end

module Operation_metadata = Contract.Operation_metadata
module Documentation = Contract.Documentation
module Security = Contract.Security
module Openapi_renderer = Openapi
module Openapi = Contract.Openapi

let schema_of_metadata (type a) (metadata : a Metadata.t) : Contract.Schema.t =
  Contract.Schema.v ?name:metadata.schema_name metadata.schema
;;

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

    module Io : Base.Monad.S with type 'a t = 'a io

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
    val route : meth -> string -> (req -> resp io) -> app_builder
    val param : req -> string -> string
    val query : req -> string -> string option
    val header : req -> string -> string option
    val body_to_string : max_bytes:int -> req -> (string, body_read_error) Result.t io
    val respond_empty : ?status:status_code -> unit -> resp io
    val respond_string : ?status:status_code -> string -> resp io
    val respond_html : ?status:status_code -> string -> resp io
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

module Parameter = struct
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t

    include Metadatable with type t := t
  end

  let v
        (type a)
        ~schema
        ?schema_name
        ?tags
        ~description
        ~(of_string : string -> (a, string) Result.t)
        ()
    : (module S with type t = a)
    =
    (module struct
      type t = a

      let of_string = of_string
      let metadata : t Metadata.t = Metadata.v ~schema ?schema_name ?tags ~description ()
    end)
  ;;

  let string ?schema_name ?tags ~description () =
    v
      ~schema:(`Assoc [ "type", `String "string" ])
      ?schema_name
      ?tags
      ~description
      ~of_string:(fun value -> Ok value)
      ()
  ;;

  let int ?schema_name ?tags ~description () =
    v
      ~schema:(`Assoc [ "type", `String "integer" ])
      ?schema_name
      ?tags
      ~description
      ~of_string:(fun value ->
        match Int.of_string_opt value with
        | Some value -> Ok value
        | None -> Error "expected an integer")
      ()
  ;;

  let int64 ?schema_name ?tags ~description () =
    v
      ~schema:(`Assoc [ "type", `String "integer"; "format", `String "int64" ])
      ?schema_name
      ?tags
      ~description
      ~of_string:(fun value ->
        try Ok (Int64.of_string value) with
        | _ -> Error "expected a 64-bit integer")
      ()
  ;;

  let float ?schema_name ?tags ~description () =
    v
      ~schema:(`Assoc [ "type", `String "number"; "format", `String "double" ])
      ?schema_name
      ?tags
      ~description
      ~of_string:(fun value ->
        try
          let value = Float.of_string value in
          if Stdlib.Float.is_finite value then
            Ok value
          else
            Error "expected a finite number"
        with
        | _ -> Error "expected a number")
      ()
  ;;

  let bool ?schema_name ?tags ~description () =
    v
      ~schema:(`Assoc [ "type", `String "boolean" ])
      ?schema_name
      ?tags
      ~description
      ~of_string:(function
        | "true" -> Ok true
        | "false" -> Ok false
        | _ -> Error "expected true or false")
      ()
  ;;
end

module Param = Parameter
module Query = Parameter

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

module Json_payload = struct
  module type S = sig
    type t

    include Metadatable with type t := t

    val of_yojson : Yojson.Safe.t -> (t, string) Result.t
    val to_yojson : t -> Yojson.Safe.t
  end
end

module Decode_error = struct
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
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:t_jsonschema
      ~schema_name:"DecodeError"
      ~description:"Request decoding error"
      ~tags:[ "errors" ]
      ()
  ;;
end

module Default_decode_error_payload = struct
  type t =
    { code : string
    ; message : string
    }
  [@@deriving to_yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:t_jsonschema
      ~schema_name:"TypedEndpointDecodeError"
      ~description:"A request rejected before the endpoint handler runs"
      ()
  ;;

  let source = function
    | `Path -> "path"
    | `Query -> "query"
  ;;

  let of_decode_error : Decode_error.t -> t = function
    | Invalid_parameter { source = parameter_source; name; _ } ->
      { code = "invalid_parameter"
      ; message = "invalid " ^ source parameter_source ^ " parameter " ^ name
      }
    | Missing_parameter { source = parameter_source; name } ->
      { code = "missing_parameter"
      ; message = "missing " ^ source parameter_source ^ " parameter " ^ name
      }
    | Invalid_json _ ->
      { code = "invalid_json"; message = "request body is not valid JSON" }
    | Invalid_body _ ->
      { code = "invalid_body"
      ; message = "request body does not match the declared schema"
      }
    | Unsupported_media_type _ ->
      { code = "unsupported_media_type"
      ; message = "request content type is not supported"
      }
    | Body_too_large { max_bytes } ->
      { code = "body_too_large"
      ; message = "request body exceeds " ^ Int.to_string max_bytes ^ " bytes"
      }
  ;;
end

module Make (B : Backend.S) = struct
  module B = B
  module Io = B.Io
  open Io.Let_syntax

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

  module Dsl = struct
    type never = |

    module Request = struct
      let default_max_body_bytes = 1_048_576

      type _ t =
        | Empty : unit t
        | JSON :
            { payload : (module Request_payload.S with type t = 'a)
            ; max_body_bytes : int
            }
            -> 'a t
        | PlainText :
            { metadata : Documentation.t
            ; max_body_bytes : int
            }
            -> string t
        | Binary :
            { metadata : Documentation.t
            ; max_body_bytes : int
            }
            -> string t

      let empty = Empty

      let json
            (type a)
            ?(max_body_bytes = default_max_body_bytes)
            (module R : Request_payload.S with type t = a)
        : a t
        =
        JSON { payload = (module R); max_body_bytes }
      ;;

      let text ?(max_body_bytes = default_max_body_bytes) ~description () : string t =
        PlainText { metadata = Documentation.v ~description (); max_body_bytes }
      ;;

      let binary ?(max_body_bytes = default_max_body_bytes) ~description () : string t =
        Binary { metadata = Documentation.v ~description (); max_body_bytes }
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
        ; security : Security.requirement list
        }

      let request =
        { resolve = (fun request -> return (Ok request)); responses = []; security = [] }
      ;;

      let return value =
        { resolve = (fun _request -> Io.return (Ok value))
        ; responses = []
        ; security = []
        }
      ;;

      let empty = return ()

      let map context ~f =
        { context with
          resolve =
            (fun request ->
              let%map result = context.resolve request in
              Result.map result ~f)
        }
      ;;

      let both left right =
        let resolve request =
          let%bind left_result = left.resolve request in
          match left_result with
          | Error rejection -> Io.return (Error rejection)
          | Ok left_value ->
            let%map right_result = right.resolve request in
            Result.map right_result ~f:(fun right_value -> left_value, right_value)
        in
        { resolve
        ; responses = left.responses @ right.responses
        ; security = Security.combine_alternatives left.security right.security
        }
      ;;

      let map2 left right ~f =
        map (both left right) ~f:(fun (left, right) -> f left right)
      ;;

      module Applicative = Base.Applicative.Make_using_map2 (struct
          type nonrec 'a t = 'a t

          let return = return
          let map2 = map2
          let map = `Custom map
        end)

      include Applicative

      module Let_syntax = struct
        let return = return
        let ( >>| ) = ( >>| )
        let ( <*> ) = ( <*> )
        let ( *> ) = ( *> )
        let ( <* ) = ( <* )

        module Let_syntax = struct
          let return = return
          let map = map
          let both = both

          module Open_on_rhs = struct end
        end
      end
    end

    module Dependency = struct
      let value = Context.return

      let of_request resolve =
        { Context.resolve =
            (fun request ->
              let%map dependency = resolve request in
              Ok dependency)
        ; responses = []
        ; security = []
        }
      ;;
    end

    module Guard = struct
      let v ?(security = []) ~status ~response ~check () =
        let resolve request =
          let%map result = check request in
          Result.map_error result ~f:(fun error ->
            Context.Rejected { status; response; error })
        in
        { Context.resolve
        ; responses = [ Context.Declared_response { status; response } ]
        ; security
        }
      ;;
    end

    module Decode_error_response = struct
      type t =
        | T :
            { response : 'a Response.t
            ; map : Decode_error.t -> 'a
            }
            -> t

      let json ~payload ~map = T { response = Response.json payload; map }

      let default =
        json
          ~payload:(module Default_decode_error_payload)
          ~map:Default_decode_error_payload.of_decode_error
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
      : type h f. (h, f) path -> h -> B.req -> (f, Decode_error.t) Result.t
      =
      fun pattern handler req0 ->
      match pattern with
      | End -> Ok handler
      | Static (_seg, rest) -> apply_path rest handler req0
      | Param (name, (module P : Param.S with type t = _), rest) ->
        let raw = B.param req0 name in
        (match P.of_string raw with
         | Error error ->
           Error
             (Decode_error.Invalid_parameter { source = `Path; name; value = raw; error })
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
         | Error error ->
           Error
             (Decode_error.Invalid_parameter
                { source = `Query; name; value = Option.value raw_opt ~default:""; error })
         | Ok v_opt ->
           let handler' = handler v_opt in
           apply_path rest handler' req0)
      | QueryReq (name, (module Q : Query.S with type t = _), rest) ->
        let raw_opt = B.query req0 name in
        let parsed =
          match raw_opt with
          | None -> Error (`Missing : [ `Missing | `Invalid of string ])
          | Some s -> Result.map_error (Q.of_string s) ~f:(fun error -> `Invalid error)
        in
        (match parsed with
         | Error `Missing ->
           Error (Decode_error.Missing_parameter { source = `Query; name })
         | Error (`Invalid error) ->
           Error
             (Decode_error.Invalid_parameter
                { source = `Query; name; value = Option.value raw_opt ~default:""; error })
         | Ok v_opt ->
           let handler' = handler v_opt in
           apply_path rest handler' req0)
    ;;

    let media_type request =
      B.header request "content-type"
      |> Option.map ~f:(fun value ->
        value
        |> String.lsplit2 ~on:';'
        |> Option.value_map ~default:value ~f:fst
        |> String.strip
        |> String.lowercase)
    ;;

    let is_json_media_type = function
      | "application/json" -> true
      | value ->
        String.is_prefix value ~prefix:"application/"
        && String.is_suffix value ~suffix:"+json"
    ;;

    let parse_request
      : type req. req Request.t -> B.req -> (req, Decode_error.t) Result.t B.io
      =
      fun spec req0 ->
      match spec with
      | Request.Empty -> return (Ok ())
      | Request.PlainText { max_body_bytes; _ } ->
        let actual = media_type req0 in
        if not (Option.value_map actual ~default:false ~f:(String.equal "text/plain"))
        then
          return
            (Error
               (Decode_error.Unsupported_media_type
                  { expected = [ "text/plain" ]; actual }))
        else (
          let%map body = B.body_to_string ~max_bytes:max_body_bytes req0 in
          Result.map_error body ~f:(fun `Too_large ->
            Decode_error.Body_too_large { max_bytes = max_body_bytes }))
      | Request.Binary { max_body_bytes; _ } ->
        let actual = media_type req0 in
        if
          not
            (Option.value_map
               actual
               ~default:false
               ~f:(String.equal "application/octet-stream"))
        then
          return
            (Error
               (Decode_error.Unsupported_media_type
                  { expected = [ "application/octet-stream" ]; actual }))
        else (
          let%map body = B.body_to_string ~max_bytes:max_body_bytes req0 in
          Result.map_error body ~f:(fun `Too_large ->
            Decode_error.Body_too_large { max_bytes = max_body_bytes }))
      | Request.JSON { payload = (module Rq); max_body_bytes } ->
        let actual = media_type req0 in
        if not (Option.value_map actual ~default:false ~f:is_json_media_type) then
          return
            (Error
               (Decode_error.Unsupported_media_type
                  { expected = [ "application/json"; "application/*+json" ]; actual }))
        else (
          let%bind body = B.body_to_string ~max_bytes:max_body_bytes req0 in
          match body with
          | Error `Too_large ->
            return (Error (Decode_error.Body_too_large { max_bytes = max_body_bytes }))
          | Ok body ->
            let json =
              try Ok (Yojson.Safe.from_string body) with
              | Yojson.Json_error error -> Error error
            in
            (match json with
             | Error error -> return (Error (Decode_error.Invalid_json { error }))
             | Ok json ->
               (match Rq.of_yojson json with
                | Ok value -> return (Ok value)
                | Error error -> return (Error (Decode_error.Invalid_body { error })))))
    ;;

    let respond_ok_with_status
      : type a. status:B.status_code -> a Response.t -> a -> B.resp B.io
      =
      fun ~status spec v ->
      match spec.payload with
      | Response.Empty -> B.respond_empty ~status ()
      | Response.PlainText -> B.respond_string ~status v
      | Response.JsonRaw -> B.respond_json ~status v
      | Response.Json (module P) -> B.respond_json ~status (P.to_yojson v)
    ;;

    let status_of_decode_error : Decode_error.t -> B.client_error_status = function
      | Invalid_parameter _ | Missing_parameter _ | Invalid_json _ | Invalid_body _ ->
        `Bad_request
      | Unsupported_media_type _ -> `Unsupported_media_type
      | Body_too_large _ -> `Request_entity_too_large
    ;;

    let render_decode_error_response (Decode_error_response.T policy) error =
      let status = ((status_of_decode_error error :> B.status) :> B.status_code) in
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
         , 'terminal
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
      ; pattern : ('h, 'terminal) path
      ; invoke :
          'terminal
          -> 'context
          -> 'req
          -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) resp
               B.io
      ; context : 'context Context.t
      ; request : 'req Request.t
      ; responses :
          ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb
      ; metadata : Operation_metadata.t option
      ; decode_error : Decode_error_response.t option
      }

    type ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) responses =
      (never, never, never, never, never, never, never, never, never) rb
      -> ('ok, 'created, 'code2xx, 'nf, 'bad, 'code4xx, 'ise, 'code5xx, 'code) rb

    let mk
          (type h terminal context req ok created code2xx nf bad code4xx ise code5xx code)
          (meth : B.meth)
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ?decode_error
          ~(invoke :
             terminal
             -> context
             -> req
             -> (ok, created, code2xx, nf, bad, code4xx, ise, code5xx, code) resp B.io)
          ~(context : context Context.t)
          ~(request : req Request.t)
          ~(path : (h, terminal) path)
          ~(responses :
             (ok, created, code2xx, nf, bad, code4xx, ise, code5xx, code) responses)
          ()
      : ( h
          , terminal
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
      ; invoke
      ; context
      ; request
      ; responses = responses RNil
      ; metadata =
          metadata_of_opts ?summary ?tags ?deprecated ?operation_id ?description ()
      ; decode_error
      }
    ;;

    let render_resp
      : type h terminal context req ok created code2xx nf bad code4xx ise code5xx code.
        ( h
          , terminal
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
        | Request.PlainText { metadata; max_body_bytes } ->
          Text_body { metadata; max_body_bytes }
        | Request.Binary { metadata; max_body_bytes } ->
          Binary_body { metadata; max_body_bytes }
        | Request.JSON { payload = (module Rq); max_body_bytes } ->
          Json_body
            { schema = schema_of_metadata Rq.metadata
            ; metadata = documentation_of_metadata Rq.metadata
            ; max_body_bytes
            }
      ;;

      let response_payload_spec_of_response
        : type a. a Response.t -> Contract.response_payload
        =
        fun r ->
        match r.payload with
        | Response.Empty -> { metadata = r.metadata; content = [] }
        | Response.PlainText -> { metadata = r.metadata; content = [ Text ] }
        | Response.JsonRaw ->
          { metadata = r.metadata; content = [ Json [ Contract.Schema.v (`Bool true) ] ] }
        | Response.Json (module P) ->
          { metadata = r.metadata; content = [ Json [ schema_of_metadata P.metadata ] ] }
      ;;

      let response_specs_of_decode_error
            (Decode_error_response.T policy)
            ~(statuses : B.client_error_status list)
        =
        List.map statuses ~f:(fun status ->
          { Contract.status = B.code_of_status ((status :> B.status) :> B.status_code)
          ; payload = response_payload_spec_of_response policy.response
          })
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
          ; schema = schema_of_metadata P.metadata
          ; metadata = documentation_of_metadata P.metadata
          }
          :: path_params rest
        | Query (name, (module Q : Query.S with type t = _), rest) ->
          { name
          ; kind = `Query
          ; required = false
          ; schema = schema_of_metadata Q.metadata
          ; metadata = documentation_of_metadata Q.metadata
          }
          :: path_params rest
        | QueryReq (name, (module Q : Query.S with type t = _), rest) ->
          { name
          ; kind = `Query
          ; required = true
          ; schema = schema_of_metadata Q.metadata
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

      let request_decode_statuses
        : type request. request Request.t -> B.client_error_status list
        = function
        | Request.Empty -> []
        | Request.PlainText _ -> [ `Request_entity_too_large; `Unsupported_media_type ]
        | Request.Binary _ -> [ `Request_entity_too_large; `Unsupported_media_type ]
        | Request.JSON _ ->
          [ `Bad_request; `Request_entity_too_large; `Unsupported_media_type ]
      ;;

      let decode_statuses pattern request =
        let statuses = request_decode_statuses request in
        let statuses =
          if path_has_parsers pattern then
            `Bad_request :: statuses
          else
            statuses
        in
        List.dedup_and_sort statuses ~compare:(fun left right ->
          Int.compare
            (B.code_of_status ((left :> B.status) :> B.status_code))
            (B.code_of_status ((right :> B.status) :> B.status_code)))
      ;;
    end

    module Route = struct
      type t =
        { meth : B.meth
        ; path : string
        ; handler : Decode_error_response.t -> B.req -> B.resp B.io
        ; contract : Decode_error_response.t -> Contract.route
        }
    end

    module Unsafe = struct
      let route ~meth ~path ~handler =
        { Route.meth
        ; path
        ; handler = (fun _decode_error -> handler)
        ; contract =
            (fun _decode_error ->
              { Contract.meth = meth_to_string meth; path; endpoint = None })
        }
      ;;
    end

    module Group = struct
      type t =
        { prefix : string list
        ; metadata : Operation_metadata.t
        ; routes : Route.t list
        ; decode_error : Decode_error_response.t option
        }

      type 'context route = Contextual_route of ('context Context.t -> Route.t)

      let v ?(prefix = []) ?decode_error ~metadata routes =
        { prefix; metadata; routes; decode_error }
      ;;

      let make ?prefix ?decode_error ?summary ?tags ?deprecated ~description routes =
        v
          ?prefix
          ?decode_error
          ~metadata:(Operation_metadata.v ?summary ?tags ?deprecated ~description ())
          routes
      ;;

      let v_with_context ?prefix ?decode_error ~metadata ~context routes =
        let routes =
          List.map routes ~f:(fun (Contextual_route attach) -> attach context)
        in
        v ?prefix ?decode_error ~metadata routes
      ;;

      let make_with_context
            ?prefix
            ?decode_error
            ?summary
            ?tags
            ?deprecated
            ~description
            ~context
            routes
        =
        v_with_context
          ?prefix
          ?decode_error
          ~metadata:(Operation_metadata.v ?summary ?tags ?deprecated ~description ())
          ~context
          routes
      ;;
    end

    let compare_path_specificity left right =
      let specificity path =
        String.split path ~on:'/'
        |> List.filter ~f:(Fn.non String.is_empty)
        |> List.map ~f:(fun segment ->
          if String.is_prefix segment ~prefix:":" then
            1
          else
            0)
      in
      List.compare Int.compare (specificity left) (specificity right)
    ;;

    let build_app ~decode_error (groups : Group.t list) : B.app_builder =
      let compile_route
            ~(prefix : string)
            ~(decode_error : Decode_error_response.t)
            (r : Route.t)
        : B.app_builder
        =
        let full_path = Contract.full_path ~prefix r.path in
        B.route r.meth full_path (r.handler decode_error)
      in
      let routes =
        List.concat_map groups ~f:(fun group ->
          let prefix = Contract.prefix_to_string group.prefix in
          let decode_error = Option.value group.decode_error ~default:decode_error in
          List.map group.routes ~f:(fun route -> prefix, decode_error, route))
        |> List.stable_sort
             ~compare:(fun (left_prefix, _, left) (right_prefix, _, right) ->
               let full_path prefix route = Contract.full_path ~prefix route.Route.path in
               compare_path_specificity
                 (full_path left_prefix left)
                 (full_path right_prefix right))
      in
      List.fold routes ~init:B.empty ~f:(fun app (prefix, decode_error, route) ->
        B.combine app (compile_route ~prefix ~decode_error route))
    ;;

    module Compiled = struct
      type t =
        { contract : Contract.Compiled.t
        ; app : B.app_builder
        }

      let app compiled = compiled.app

      let openapi ?(config = Openapi.Config.default) compiled =
        Openapi_renderer.render ~config compiled.contract
      ;;
    end

    module Compile_error = struct
      type t = Contract.Compile_error.t =
        | Duplicate_route of
            { meth : string
            ; path : string
            }
        | Ambiguous_route of
            { meth : string
            ; path : string
            ; conflicts_with : string
            }
        | Invalid_group_prefix_segment of string
        | Invalid_route_path of
            { meth : string
            ; path : string
            }
        | Mismatched_path_parameters of
            { meth : string
            ; path : string
            ; declared : string list
            ; captures : string list
            }
        | Duplicate_operation_id of string
        | Duplicate_parameter of
            { meth : string
            ; path : string
            ; kind : Contract.param_kind
            ; name : string
            }
        | Duplicate_response_status of
            { meth : string
            ; path : string
            ; status : int
            }
        | Invalid_response_status of
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

      let to_string = Contract.Compile_error.to_string
    end

    let compile ?(decode_error = Decode_error_response.default) (groups : Group.t list)
      : (Compiled.t, Compile_error.t list) Result.t
      =
      let contract_groups =
        List.map groups ~f:(fun group ->
          let decode_error = Option.value group.decode_error ~default:decode_error in
          { Contract.prefix = group.prefix
          ; metadata = group.metadata
          ; routes = List.map group.routes ~f:(fun route -> route.contract decode_error)
          })
      in
      Contract.compile contract_groups
      |> Result.map ~f:(fun contract ->
        { Compiled.contract; app = build_app ~decode_error groups })
    ;;

    let compile_exn ?decode_error groups =
      match compile ?decode_error groups with
      | Ok compiled -> compiled
      | Error errors ->
        errors
        |> List.map ~f:Contract.Compile_error.to_string
        |> String.concat ~sep:"; "
        |> failwith
    ;;

    let make_route
          ~context
          ~invoke
          ~meth
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ?decode_error
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
          ?decode_error
          ~invoke
          ~context
          ~request
          ~path
          ~responses
          ()
      in
      let path_str = path_to_string b.pattern in
      let resolve_decode_error inherited =
        Option.value b.decode_error ~default:inherited
      in
      let render_decode_error inherited error =
        render_decode_error_response (resolve_decode_error inherited) error
      in
      let wrapped inherited (req0 : B.req) : B.resp B.io =
        let%bind context_result = b.context.resolve req0 in
        match context_result with
        | Error rejection -> render_context_rejection rejection
        | Ok context ->
          (match apply_path b.pattern f req0 with
           | Error error -> render_decode_error inherited error
           | Ok f' ->
             let%bind parsed = parse_request b.request req0 in
             (match parsed with
              | Error error -> render_decode_error inherited error
              | Ok body ->
                let%bind r = b.invoke f' context body in
                render_resp b r))
      in
      let decode_statuses = Openapi_adapter.decode_statuses b.pattern b.request in
      let contract inherited =
        let decode_error_responses =
          Openapi_adapter.response_specs_of_decode_error
            (resolve_decode_error inherited)
            ~statuses:decode_statuses
        in
        let endpoint : Contract.endpoint =
          { meth = meth_to_string b.meth
          ; path = path_str
          ; metadata = b.metadata
          ; params = Openapi_adapter.path_params b.pattern
          ; request_body = Openapi_adapter.request_body_spec_of_request b.request
          ; responses = Openapi_adapter.collect_responses b.responses
          ; decode_error_responses
          ; context_responses = Openapi_adapter.response_specs_of_context b.context
          ; security = b.context.security
          ; response_families = Openapi_adapter.response_families b.responses
          }
        in
        { Contract.meth = meth_to_string b.meth
        ; path = path_str
        ; endpoint = Some endpoint
        }
      in
      { Route.meth = b.meth; path = path_str; handler = wrapped; contract }
    ;;

    let make_with
          ~context
          ~meth
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ?decode_error
          ~request
          ~path
          ~responses
          f
      =
      make_route
        ~context
        ~invoke:(fun handler context body -> handler context body)
        ~meth
        ?summary
        ?tags
        ?deprecated
        ?operation_id
        ?description
        ?decode_error
        ~request
        ~path
        ~responses
        f
    ;;

    let make
          ~meth
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ?decode_error
          ~request
          ~path
          ~responses
          f
      =
      make_route
        ~context:Context.empty
        ~invoke:(fun handler () body -> handler body)
        ~meth
        ?summary
        ?tags
        ?deprecated
        ?operation_id
        ?description
        ?decode_error
        ~request
        ~path
        ~responses
        f
    ;;

    let make_in_group
          ~meth
          ?summary
          ?tags
          ?deprecated
          ?operation_id
          ?description
          ?decode_error
          ~request
          ~path
          ~responses
          f
      =
      Group.Contextual_route
        (fun context ->
          make_with
            ~context
            ~meth
            ?summary
            ?tags
            ?deprecated
            ?operation_id
            ?description
            ?decode_error
            ~request
            ~path
            ~responses
            f)
    ;;
  end
end
