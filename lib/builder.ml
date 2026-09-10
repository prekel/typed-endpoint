open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson
module Json_schema = Json_schema

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

module Principal = struct
  type 'identity t =
    { identity : 'identity
    ; scopes : string list
    }

  let v ?(scopes = []) ~identity () =
    { identity; scopes = List.dedup_and_sort scopes ~compare:String.compare }
  ;;

  let identity principal = principal.identity
  let scopes principal = principal.scopes
  let has_scope principal scope = List.mem principal.scopes scope ~equal:String.equal
end

module Route_info = struct
  type t =
    { operation_id : string option
    ; method_ : string
    ; path_template : string
    ; tags : string list
    ; security : Security.requirement list
    }
end

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

module Method = struct
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

module Status = struct
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

  let code : t -> int = function
    | `Continue -> 100
    | `Switching_protocols -> 101
    | `Processing -> 102
    | `Checkpoint -> 103
    | `OK -> 200
    | `Created -> 201
    | `Accepted -> 202
    | `Non_authoritative_information -> 203
    | `No_content -> 204
    | `Reset_content -> 205
    | `Partial_content -> 206
    | `Multi_status -> 207
    | `Already_reported -> 208
    | `Im_used -> 226
    | `Multiple_choices -> 300
    | `Moved_permanently -> 301
    | `Found -> 302
    | `See_other -> 303
    | `Not_modified -> 304
    | `Use_proxy -> 305
    | `Switch_proxy -> 306
    | `Temporary_redirect -> 307
    | `Permanent_redirect -> 308
    | `Bad_request -> 400
    | `Unauthorized -> 401
    | `Payment_required -> 402
    | `Forbidden -> 403
    | `Not_found -> 404
    | `Method_not_allowed -> 405
    | `Not_acceptable -> 406
    | `Proxy_authentication_required -> 407
    | `Request_timeout -> 408
    | `Conflict -> 409
    | `Gone -> 410
    | `Length_required -> 411
    | `Precondition_failed -> 412
    | `Request_entity_too_large -> 413
    | `Request_uri_too_long -> 414
    | `Unsupported_media_type -> 415
    | `Requested_range_not_satisfiable -> 416
    | `Expectation_failed -> 417
    | `I_m_a_teapot -> 418
    | `Enhance_your_calm -> 420
    | `Unprocessable_entity -> 422
    | `Locked -> 423
    | `Failed_dependency -> 424
    | `Upgrade_required -> 426
    | `Precondition_required -> 428
    | `Too_many_requests -> 429
    | `Request_header_fields_too_large -> 431
    | `No_response -> 444
    | `Retry_with -> 449
    | `Blocked_by_windows_parental_controls -> 450
    | `Wrong_exchange_server -> 451
    | `Client_closed_request -> 499
    | `Internal_server_error -> 500
    | `Not_implemented -> 501
    | `Bad_gateway -> 502
    | `Service_unavailable -> 503
    | `Gateway_timeout -> 504
    | `Http_version_not_supported -> 505
    | `Variant_also_negotiates -> 506
    | `Insufficient_storage -> 507
    | `Loop_detected -> 508
    | `Bandwidth_limit_exceeded -> 509
    | `Not_extended -> 510
    | `Network_authentication_required -> 511
    | `Network_read_timeout_error -> 598
    | `Network_connect_timeout_error -> 599
    | `Code code -> code
  ;;
end

module Backend = struct
  module type S = sig
    type req
    type resp
    type 'a io

    module Io : Base.Monad.S with type 'a t = 'a io

    type app_builder

    val route : Method.t -> string -> (req -> resp io) -> app_builder
    val param : req -> string -> string
    val query : req -> string -> string list
    val header : req -> string -> string option
    val body_to_string : max_bytes:int -> req -> (string, [ `Too_large ]) Result.t io

    val respond
      :  ?status:Status.t
      -> headers:(string * string) list
      -> body:string
      -> unit
      -> resp io

    val respond_empty : ?status:Status.t -> unit -> resp io
    val respond_string : ?status:Status.t -> string -> resp io
    val respond_html : ?status:Status.t -> string -> resp io
    val respond_json : ?status:Status.t -> Yojson.Safe.t -> resp io
    val combine : app_builder -> app_builder -> app_builder
    val empty : app_builder
  end
end

module Runtime_error = struct
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

  let to_string = function
    | Undeclared_response_case { meth; path; status; declared } ->
      let declared = declared |> List.map ~f:Int.to_string |> String.concat ~sep:", " in
      "handler returned undeclared response case for status "
      ^ Int.to_string status
      ^ " for "
      ^ meth
      ^ " "
      ^ path
      ^ "; declared: ["
      ^ declared
      ^ "]"
    | Invalid_response_header { name; reason } ->
      "invalid response header " ^ name ^ ": " ^ reason
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
      ~schema:(Json_schema.string_exn ())
      ?schema_name
      ?tags
      ~description
      ~of_string:(fun value -> Ok value)
      ()
  ;;

  let int ?schema_name ?tags ~description () =
    v
      ~schema:(Json_schema.integer_exn ())
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
      ~schema:(Json_schema.integer_exn ~format:`Int64 ())
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
      ~schema:(Json_schema.number_exn ~format:`Double ())
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
      ~schema:(Json_schema.boolean ())
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

module Header = struct
  module type S = sig
    type t

    val of_string : string -> (t, string) Result.t
    val to_string : t -> string

    include Metadatable with type t := t
  end

  let v
        (type a)
        ~schema
        ?schema_name
        ?tags
        ~description
        ~(of_string : string -> (a, string) Result.t)
        ~(to_string : a -> string)
        ()
    : (module S with type t = a)
    =
    (module struct
      type t = a

      let of_string = of_string
      let to_string = to_string
      let metadata : t Metadata.t = Metadata.v ~schema ?schema_name ?tags ~description ()
    end)
  ;;

  let string ?schema_name ?tags ~description () =
    v
      ~schema:(Json_schema.string_exn ())
      ?schema_name
      ?tags
      ~description
      ~of_string:(fun value -> Ok value)
      ~to_string:Fn.id
      ()
  ;;

  let int ?schema_name ?tags ~description () =
    v
      ~schema:(Json_schema.integer_exn ())
      ?schema_name
      ?tags
      ~description
      ~of_string:(fun value ->
        match Int.of_string_opt value with
        | Some value -> Ok value
        | None -> Error "expected an integer")
      ~to_string:Int.to_string
      ()
  ;;

  let int64 ?schema_name ?tags ~description () =
    v
      ~schema:(Json_schema.integer_exn ~format:`Int64 ())
      ?schema_name
      ?tags
      ~description
      ~of_string:(fun value ->
        try Ok (Int64.of_string value) with
        | _ -> Error "expected a 64-bit integer")
      ~to_string:Int64.to_string
      ()
  ;;

  let bool ?schema_name ?tags ~description () =
    v
      ~schema:(Json_schema.boolean ())
      ?schema_name
      ?tags
      ~description
      ~of_string:(function
        | "true" -> Ok true
        | "false" -> Ok false
        | _ -> Error "expected true or false")
      ~to_string:Bool.to_string
      ()
  ;;

  type _ t =
    | Required : string * (module S with type t = 'a) -> 'a t
    | Optional : string * (module S with type t = 'a) -> 'a option t

  let required name codec = Required (name, codec)
  let optional name codec = Optional (name, codec)

  let name : type a. a t -> string = function
    | Required (name, _) | Optional (name, _) -> name
  ;;
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

module Default_decode_error_payload = struct
  type t =
    { code : string
    ; message : string
    }
  [@@deriving to_yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:(Json_schema.of_ppx t_jsonschema)
      ~schema_name:"TypedEndpointDecodeError"
      ~description:"A request rejected before the endpoint handler runs"
      ()
  ;;

  let source = function
    | `Path -> "path"
    | `Query -> "query"
    | `Header -> "header"
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
    | Duplicate_parameter { source = parameter_source; name } ->
      { code = "duplicate_parameter"
      ; message = "duplicate " ^ source parameter_source ^ " parameter " ^ name
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
  module Io = B.Io
  open Io.Let_syntax

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
      | PlainText : string payload
      | Empty : unit payload

    type _ t =
      | Payload :
          { payload : 'a payload
          ; metadata : Documentation.t
          }
          -> 'a t
      | With_header : 'header Header.t * 'body t -> ('header * 'body) t

    let json : type a. (module Response_payload.S with type t = a) -> a t =
      fun (module P : Response_payload.S with type t = a) ->
      Payload
        { payload = Json (module P); metadata = documentation_of_metadata P.metadata }
    ;;

    let text ~description () : string t =
      Payload { payload = PlainText; metadata = Documentation.v ~description () }
    ;;

    let empty ~description () : unit t =
      Payload { payload = Empty; metadata = Documentation.v ~description () }
    ;;

    let with_header header response = With_header (header, response)

    type 'a case_data =
      { id : int
      ; status : Status.t
      ; response : 'a t
      }

    type declared_case = Declared_case : 'a case_data -> declared_case

    type cases =
      | One_case of declared_case
      | Both_cases of cases * cases

    type reply = Reply : 'a case_data * 'a -> reply

    type 'a case =
      { cases : cases
      ; make_reply : 'a -> reply
      }

    let fresh_case_id =
      let next = Stdlib.Atomic.make 0 in
      fun () -> Stdlib.Atomic.fetch_and_add next 1
    ;;

    let case status response =
      let data = { id = fresh_case_id (); status; response } in
      { cases = One_case (Declared_case data)
      ; make_reply = (fun value -> Reply (data, value))
      }
    ;;

    let combine (type a b) (left : a case) (right : b case) : never case =
      { cases = Both_cases (left.cases, right.cases)
      ; make_reply =
          (fun impossible ->
            match impossible with
            | _ -> .)
      }
    ;;
  end

  let case = Response.case

  type reply = Response.reply
  type response_cases = Response.cases

  let ( <|> ) = Response.combine
  let respond case value = Io.return (case.Response.make_reply value)

  module Context = struct
    type rejection =
      | Rejected :
          { status : Status.client_error
          ; response : 'error Response.t
          ; error : 'error
          }
          -> rejection

    type declared_response =
      | Declared_response :
          { status : Status.client_error
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
      { resolve = (fun _request -> Io.return (Ok value)); responses = []; security = [] }
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

    let map2 left right ~f = map (both left right) ~f:(fun (left, right) -> f left right)

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

    let authenticate = v
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
        string * (module Parameter.S with type t = 'p) * ('h, 'f) path
        -> ('p -> 'h, 'f) path
    | Query :
        string * (module Parameter.S with type t = 'q) * ('h, 'f) path
        -> ('q option -> 'h, 'f) path
    | QueryReq :
        string * (module Parameter.S with type t = 'q) * ('h, 'f) path
        -> ('q -> 'h, 'f) path
    | Request_header : 'header Header.t * ('h, 'f) path -> ('header -> 'h, 'f) path

  let path_to_string : type h f. (h, f) path -> string =
    fun p ->
    let rec collect : type h f. (h, f) path -> string list -> string list =
      fun p acc ->
      match p with
      | End -> acc
      | Static (seg, rest) -> collect rest (seg :: acc)
      | Param (name, (module P : Parameter.S with type t = _), rest) ->
        collect rest ((":" ^ name) :: acc)
      | Query (_, _, rest) -> collect rest acc
      | QueryReq (_, _, rest) -> collect rest acc
      | Request_header (_, rest) -> collect rest acc
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
      Some (Operation_metadata.v ?summary ~tags ~deprecated ?operation_id ~description ())
  ;;

  let meth_to_string : Method.t -> string = function
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

  let rec apply_path : type h f. (h, f) path -> h -> B.req -> (f, Decode_error.t) Result.t
    =
    fun pattern handler req0 ->
    match pattern with
    | End -> Ok handler
    | Static (_seg, rest) -> apply_path rest handler req0
    | Param (name, (module P : Parameter.S with type t = _), rest) ->
      let raw = B.param req0 name in
      (match P.of_string raw with
       | Error error ->
         Error
           (Decode_error.Invalid_parameter { source = `Path; name; value = raw; error })
       | Ok v ->
         let handler' = handler v in
         apply_path rest handler' req0)
    | Query (name, (module Q : Parameter.S with type t = _), rest) ->
      let raw_values = B.query req0 name in
      let parsed =
        match raw_values with
        | [] -> Ok None
        | [ value ] ->
          Q.of_string value
          |> Result.map ~f:Option.some
          |> Result.map_error ~f:(fun error -> `Parse error)
        | _ -> Error `Duplicate
      in
      (match parsed with
       | Error `Duplicate ->
         Error (Decode_error.Duplicate_parameter { source = `Query; name })
       | Error (`Parse error) ->
         Error
           (Decode_error.Invalid_parameter
              { source = `Query
              ; name
              ; value = List.hd raw_values |> Option.value ~default:""
              ; error
              })
       | Ok v_opt ->
         let handler' = handler v_opt in
         apply_path rest handler' req0)
    | QueryReq (name, (module Q : Parameter.S with type t = _), rest) ->
      let raw_values = B.query req0 name in
      let parsed =
        match raw_values with
        | [] -> Error (`Missing : [ `Missing | `Duplicate | `Invalid of string ])
        | [ value ] ->
          Result.map_error (Q.of_string value) ~f:(fun error -> `Invalid error)
        | _ -> Error `Duplicate
      in
      (match parsed with
       | Error `Missing ->
         Error (Decode_error.Missing_parameter { source = `Query; name })
       | Error `Duplicate ->
         Error (Decode_error.Duplicate_parameter { source = `Query; name })
       | Error (`Invalid error) ->
         Error
           (Decode_error.Invalid_parameter
              { source = `Query
              ; name
              ; value = List.hd raw_values |> Option.value ~default:""
              ; error
              })
       | Ok v_opt ->
         let handler' = handler v_opt in
         apply_path rest handler' req0)
    | Request_header (header, rest) ->
      let name = Header.name header in
      (match header with
       | Header.Required (_, (module H)) ->
         (match B.header req0 name with
          | None -> Error (Decode_error.Missing_parameter { source = `Header; name })
          | Some raw ->
            (match H.of_string raw with
             | Error error ->
               Error
                 (Decode_error.Invalid_parameter
                    { source = `Header; name; value = raw; error })
             | Ok value -> apply_path rest (handler value) req0))
       | Header.Optional (_, (module H)) ->
         (match B.header req0 name with
          | None -> apply_path rest (handler None) req0
          | Some raw ->
            (match H.of_string raw with
             | Error error ->
               Error
                 (Decode_error.Invalid_parameter
                    { source = `Header; name; value = raw; error })
             | Ok value -> apply_path rest (handler (Some value)) req0)))
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
      if not (Option.value_map actual ~default:false ~f:(String.equal "text/plain")) then
        return
          (Error
             (Decode_error.Unsupported_media_type { expected = [ "text/plain" ]; actual }))
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

  let validate_response_header name value =
    if String.mem value '\r' || String.mem value '\n' then
      raise
        (Runtime_error
           (Invalid_response_header
              { name; reason = "value contains a carriage return or line feed" }))
    else
      name, value
  ;;

  let encode_response_header : type a. a Header.t -> a -> (string * string) option =
    fun header value ->
    match header with
    | Header.Required (name, (module H)) ->
      Some (validate_response_header name (H.to_string value))
    | Header.Optional (name, (module H)) ->
      Option.map value ~f:(fun value -> validate_response_header name (H.to_string value))
  ;;

  let respond_ok_with_status : type a. status:Status.t -> a Response.t -> a -> B.resp B.io
    =
    fun ~status spec value ->
    let rec render : type a. (string * string) list -> a Response.t -> a -> B.resp B.io =
      fun headers spec value ->
      match spec with
      | Response.With_header (header, response) ->
        let header = encode_response_header header (fst value) in
        let headers = Option.to_list header @ headers in
        render headers response (snd value)
      | Response.Payload { payload; _ } ->
        (match payload with
         | Response.Empty -> B.respond ~status ~headers ~body:"" ()
         | Response.PlainText ->
           B.respond
             ~status
             ~headers:(("content-type", "text/plain; charset=utf-8") :: headers)
             ~body:value
             ()
         | Response.Json (module P) ->
           B.respond
             ~status
             ~headers:(("content-type", "application/json") :: headers)
             ~body:(P.to_yojson value |> Yojson.Safe.to_string)
             ())
    in
    render [] spec value
  ;;

  let status_of_decode_error : Decode_error.t -> Status.client_error = function
    | Invalid_parameter _
    | Missing_parameter _
    | Duplicate_parameter _
    | Invalid_json _
    | Invalid_body _ -> `Bad_request
    | Unsupported_media_type _ -> `Unsupported_media_type
    | Body_too_large _ -> `Request_entity_too_large
  ;;

  let render_decode_error_response (Decode_error_response.T policy) error =
    let status = (status_of_decode_error error :> Status.t) in
    respond_ok_with_status ~status policy.response (policy.map error)
  ;;

  type ('h, 'terminal, 'context, 'req) builder =
    { meth : Method.t
    ; pattern : ('h, 'terminal) path
    ; invoke : 'terminal -> 'context -> 'req -> reply B.io
    ; context : 'context Context.t
    ; request : 'req Request.t
    ; responses : response_cases
    ; metadata : Operation_metadata.t option
    ; decode_error : Decode_error_response.t option
    }

  let mk
        (type h terminal context req)
        (meth : Method.t)
        ?summary
        ?tags
        ?deprecated
        ?operation_id
        ?description
        ?decode_error
        ~(invoke : terminal -> context -> req -> reply B.io)
        ~(context : context Context.t)
        ~(request : req Request.t)
        ~(path : (h, terminal) path)
        ~(responses : response_cases)
        ()
    : (h, terminal, context, req) builder
    =
    { meth
    ; pattern = path
    ; invoke
    ; context
    ; request
    ; responses
    ; metadata = metadata_of_opts ?summary ?tags ?deprecated ?operation_id ?description ()
    ; decode_error
    }
  ;;

  let rec response_case_list = function
    | Response.One_case declared -> [ declared ]
    | Response.Both_cases (left, right) ->
      response_case_list left @ response_case_list right
  ;;

  let render_reply b (Response.Reply (returned, value)) =
    let declared = response_case_list b.responses in
    let declared_ids, declared_statuses =
      List.fold_right declared ~init:([], []) ~f:(fun declared (ids, statuses) ->
        match declared with
        | Response.Declared_case data ->
          data.id :: ids, Status.code data.status :: statuses)
    in
    let status = Status.code returned.status in
    (match
       Runtime.ensure_declared_case
         ~meth:(meth_to_string b.meth)
         ~path:(path_to_string b.pattern)
         ~case_id:returned.id
         ~declared_case_ids:declared_ids
         ~status
         ~declared:declared_statuses
     with
     | Ok () -> ()
     | Error { Runtime.meth; path; status; declared } ->
       raise (Runtime_error (Undeclared_response_case { meth; path; status; declared })));
    respond_ok_with_status ~status:returned.status returned.response value
  ;;

  let render_context_rejection (Context.Rejected { status; response; error })
    : B.resp B.io
    =
    let status = (status :> Status.t) in
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

    let rec response_payload_spec_of_response
      : type a. a Response.t -> Contract.response_payload
      =
      fun r ->
      match r with
      | Response.With_header (header, response) ->
        let name, required, schema, metadata =
          match header with
          | Header.Required (name, (module H)) ->
            ( name
            , true
            , schema_of_metadata H.metadata
            , documentation_of_metadata H.metadata )
          | Header.Optional (name, (module H)) ->
            ( name
            , false
            , schema_of_metadata H.metadata
            , documentation_of_metadata H.metadata )
        in
        let payload = response_payload_spec_of_response response in
        { payload with
          headers = { Contract.name; required; schema; metadata } :: payload.headers
        }
      | Response.Payload { payload; metadata } ->
        (match payload with
         | Response.Empty -> { metadata; content = []; headers = [] }
         | Response.PlainText -> { metadata; content = [ Text ]; headers = [] }
         | Response.Json (module P) ->
           { metadata
           ; content = [ Json [ schema_of_metadata P.metadata ] ]
           ; headers = []
           })
    ;;

    let response_specs_of_decode_error
          (Decode_error_response.T policy)
          ~(statuses : Status.client_error list)
      =
      List.map statuses ~f:(fun status ->
        { Contract.status = Status.code (status :> Status.t)
        ; payload = response_payload_spec_of_response policy.response
        })
    ;;

    let response_specs_of_context context =
      List.map context.Context.responses ~f:(fun (Context.Declared_response declared) ->
        { Contract.status = Status.code (declared.status :> Status.t)
        ; payload = response_payload_spec_of_response declared.response
        })
    ;;

    let rec path_params : type h f. (h, f) path -> Contract.param list =
      fun p ->
      match p with
      | End -> []
      | Static (_, rest) -> path_params rest
      | Param (name, (module P : Parameter.S with type t = _), rest) ->
        { name
        ; kind = `Path
        ; required = true
        ; schema = schema_of_metadata P.metadata
        ; metadata = documentation_of_metadata P.metadata
        }
        :: path_params rest
      | Query (name, (module Q : Parameter.S with type t = _), rest) ->
        { name
        ; kind = `Query
        ; required = false
        ; schema = schema_of_metadata Q.metadata
        ; metadata = documentation_of_metadata Q.metadata
        }
        :: path_params rest
      | QueryReq (name, (module Q : Parameter.S with type t = _), rest) ->
        { name
        ; kind = `Query
        ; required = true
        ; schema = schema_of_metadata Q.metadata
        ; metadata = documentation_of_metadata Q.metadata
        }
        :: path_params rest
      | Request_header (header, rest) ->
        let name, required, schema, metadata =
          match header with
          | Header.Required (name, (module H)) ->
            ( name
            , true
            , schema_of_metadata H.metadata
            , documentation_of_metadata H.metadata )
          | Header.Optional (name, (module H)) ->
            ( name
            , false
            , schema_of_metadata H.metadata
            , documentation_of_metadata H.metadata )
        in
        { Contract.name; kind = `Header; required; schema; metadata } :: path_params rest
    ;;

    let collect_responses cases =
      response_case_list cases
      |> List.map ~f:(fun (Response.Declared_case data) ->
        { Contract.status = Status.code data.status
        ; payload = response_payload_spec_of_response data.response
        })
    ;;

    let rec path_has_parsers : type h f. (h, f) path -> bool = function
      | End -> false
      | Static (_, tail) -> path_has_parsers tail
      | Param _ | Query _ | QueryReq _ | Request_header _ -> true
    ;;

    let request_decode_statuses
      : type request. request Request.t -> Status.client_error list
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
        Int.compare (Status.code (left :> Status.t)) (Status.code (right :> Status.t)))
    ;;
  end

  type route =
    { meth : Method.t
    ; path : string
    ; metadata : Operation_metadata.t option
    ; security : Security.requirement list
    ; handler : Decode_error_response.t -> B.req -> B.resp B.io
    ; contract : Decode_error_response.t -> Contract.route
    }

  type interceptor =
    route_info:Route_info.t -> request:B.req -> next:(unit -> B.resp B.io) -> B.resp B.io

  let apply_interceptors interceptors ~route_info ~request ~next =
    List.fold_right
      interceptors
      ~init:next
      ~f:(fun interceptor next () -> interceptor ~route_info ~request ~next)
      ()
  ;;

  module Unsafe = struct
    let route ~meth ~path ~handler =
      { meth
      ; path
      ; metadata = None
      ; security = []
      ; handler = (fun _decode_error -> handler)
      ; contract =
          (fun _decode_error ->
            { Contract.meth = meth_to_string meth; path; endpoint = None })
      }
    ;;
  end

  type endpoint_route = route

  module Group = struct
    type t =
      { prefix : string list
      ; metadata : Operation_metadata.t
      ; routes : endpoint_route list
      ; decode_error : Decode_error_response.t option
      }

    type 'context route = Contextual_route of ('context Context.t -> endpoint_route)

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
      let routes = List.map routes ~f:(fun (Contextual_route attach) -> attach context) in
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

  let path_to_template path =
    String.split path ~on:'/'
    |> List.map ~f:(fun segment ->
      match String.chop_prefix segment ~prefix:":" with
      | None -> segment
      | Some name -> "{" ^ name ^ "}")
    |> String.concat ~sep:"/"
  ;;

  let route_metadata ~(group : Operation_metadata.t) (route : Operation_metadata.t option)
    : Operation_metadata.t
    =
    match route with
    | None -> group
    | Some route ->
      { route with
        tags = List.dedup_and_sort (group.tags @ route.tags) ~compare:String.compare
      }
  ;;

  let build_app ~decode_error ~interceptors (groups : Group.t list) : B.app_builder =
    let compile_route
          ~(prefix : string)
          ~(decode_error : Decode_error_response.t)
          ~(group_metadata : Operation_metadata.t)
          (r : route)
      : B.app_builder
      =
      let full_path = Contract.full_path ~prefix r.path in
      let metadata = route_metadata ~group:group_metadata r.metadata in
      let route_info : Route_info.t =
        { operation_id = metadata.operation_id
        ; method_ = meth_to_string r.meth |> String.uppercase
        ; path_template = path_to_template full_path
        ; tags = metadata.tags
        ; security = r.security
        }
      in
      let handler = r.handler decode_error in
      B.route r.meth full_path (fun request ->
        apply_interceptors interceptors ~route_info ~request ~next:(fun () ->
          handler request))
    in
    let routes =
      List.concat_map groups ~f:(fun group ->
        let prefix = Contract.prefix_to_string group.prefix in
        let decode_error = Option.value group.decode_error ~default:decode_error in
        List.map group.routes ~f:(fun route ->
          prefix, decode_error, group.metadata, route))
      |> List.stable_sort
           ~compare:(fun (left_prefix, _, _, left) (right_prefix, _, _, right) ->
             let full_path prefix route = Contract.full_path ~prefix route.path in
             compare_path_specificity
               (full_path left_prefix left)
               (full_path right_prefix right))
    in
    List.fold
      routes
      ~init:B.empty
      ~f:(fun app (prefix, decode_error, group_metadata, route) ->
        B.combine app (compile_route ~prefix ~decode_error ~group_metadata route))
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

    let to_string = Contract.Compile_error.to_string
  end

  let compile
        ?(decode_error = Decode_error_response.default)
        ?(interceptors = [])
        (groups : Group.t list)
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
      { Compiled.contract; app = build_app ~decode_error ~interceptors groups })
  ;;

  let compile_exn ?decode_error ?interceptors groups =
    match compile ?decode_error ?interceptors groups with
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
    : route
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
    let resolve_decode_error inherited = Option.value b.decode_error ~default:inherited in
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
              render_reply b r))
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
        }
      in
      { Contract.meth = meth_to_string b.meth; path = path_str; endpoint = Some endpoint }
    in
    { meth = b.meth
    ; path = path_str
    ; metadata = b.metadata
    ; security = b.context.security
    ; handler = wrapped
    ; contract
    }
  ;;

  type 'a argument =
    { name : string
    ; codec : (module Parameter.S with type t = 'a)
    }

  let arg name codec = { name; codec }

  type ('phase, 'handler, 'terminal) uri =
    { meth : Method.t
    ; path : ('handler, 'terminal) path
    }

  type (_, _) segment =
    | Static_segment : string -> ('a, 'a) segment
    | Path_segment :
        string * (module Parameter.S with type t = 'a)
        -> ('a -> 'tail, 'tail) segment
    | Optional_query_segment :
        string * (module Parameter.S with type t = 'a)
        -> ('a option -> 'tail, 'tail) segment
    | Required_query_segment :
        string * (module Parameter.S with type t = 'a)
        -> ('a -> 'tail, 'tail) segment
    | Header_segment : 'a Header.t -> ('a -> 'tail, 'tail) segment

  let prepend_segment
    : type before after final.
      (before, after) segment -> (after, final) path -> (before, final) path
    =
    fun segment tail ->
    match segment with
    | Static_segment value -> Static (value, tail)
    | Path_segment (name, codec) -> Param (name, codec, tail)
    | Optional_query_segment (name, codec) -> Query (name, codec, tail)
    | Required_query_segment (name, codec) -> QueryReq (name, codec, tail)
    | Header_segment header -> Request_header (header, tail)
  ;;

  let rec append_segment
    : type handler before after.
      (handler, before) path -> (before, after) segment -> (handler, after) path
    =
    fun path segment ->
    match path with
    | End -> prepend_segment segment End
    | Static (value, tail) -> Static (value, append_segment tail segment)
    | Param (name, codec, tail) -> Param (name, codec, append_segment tail segment)
    | Query (name, codec, tail) -> Query (name, codec, append_segment tail segment)
    | QueryReq (name, codec, tail) -> QueryReq (name, codec, append_segment tail segment)
    | Request_header (header, tail) -> Request_header (header, append_segment tail segment)
  ;;

  let meth meth = { meth; path = End }
  let get : ([ `Path ], 'terminal, 'terminal) uri = { meth = `GET; path = End }
  let post : ([ `Path ], 'terminal, 'terminal) uri = { meth = `POST; path = End }
  let put : ([ `Path ], 'terminal, 'terminal) uri = { meth = `PUT; path = End }
  let delete : ([ `Path ], 'terminal, 'terminal) uri = { meth = `DELETE; path = End }
  let patch : ([ `Path ], 'terminal, 'terminal) uri = { meth = `PATCH; path = End }

  let ( / ) builder value =
    { meth = builder.meth; path = append_segment builder.path (Static_segment value) }
  ;;

  let ( /: )
        (type handler value terminal)
        (builder : ([ `Path ], handler, value -> terminal) uri)
        ({ name; codec } : value argument)
    : ([ `Path ], handler, terminal) uri
    =
    { meth = builder.meth
    ; path = append_segment builder.path (Path_segment (name, codec))
    }
  ;;

  let ( /? )
        (type phase handler value terminal)
        (builder : (phase, handler, value option -> terminal) uri)
        ({ name; codec } : value argument)
    : ([ `Query ], handler, terminal) uri
    =
    { meth = builder.meth
    ; path = append_segment builder.path (Optional_query_segment (name, codec))
    }
  ;;

  let ( /! )
        (type phase handler value terminal)
        (builder : (phase, handler, value -> terminal) uri)
        ({ name; codec } : value argument)
    : ([ `Query ], handler, terminal) uri
    =
    { meth = builder.meth
    ; path = append_segment builder.path (Required_query_segment (name, codec))
    }
  ;;

  let header
        (type phase handler value terminal)
        (declaration : value Header.t)
        (builder : (phase, handler, value -> terminal) uri)
    : ([ `Header ], handler, terminal) uri
    =
    { meth = builder.meth
    ; path = append_segment builder.path (Header_segment declaration)
    }
  ;;

  type ('handler, 'terminal) documented =
    { meth : Method.t
    ; path : ('handler, 'terminal) path
    ; summary : string option
    ; tags : string list option
    ; deprecated : bool option
    ; operation_id : string option
    ; description : string option
    ; decode_error : Decode_error_response.t option
    }

  let documented
        (type phase handler terminal)
        ?summary
        ?tags
        ?deprecated
        ?operation_id
        ?description
        ?decode_error
        (builder : (phase, handler, terminal) uri)
    : (handler, terminal) documented
    =
    { meth = builder.meth
    ; path = builder.path
    ; summary
    ; tags
    ; deprecated
    ; operation_id
    ; description
    ; decode_error
    }
  ;;

  type ('handler, 'terminal, 'request) requested =
    { documented : ('handler, 'terminal) documented
    ; request : 'request Request.t
    }

  let accepts request documented = { documented; request }

  type ('handler, 'terminal, 'request) ready =
    { requested : ('handler, 'terminal, 'request) requested
    ; responses : response_cases
    }

  let returns responses requested = { requested; responses = responses.Response.cases }

  let handle handler ready =
    let { requested = { documented; request }; responses } = ready in
    make_route
      ~context:Context.empty
      ~invoke:(fun handler () body -> handler body)
      ~meth:documented.meth
      ?summary:documented.summary
      ?tags:documented.tags
      ?deprecated:documented.deprecated
      ?operation_id:documented.operation_id
      ?description:documented.description
      ?decode_error:documented.decode_error
      ~request
      ~path:documented.path
      ~responses
      handler
  ;;

  let handle_with ~context handler ready =
    let { requested = { documented; request }; responses } = ready in
    make_route
      ~context
      ~invoke:(fun handler context body -> handler context body)
      ~meth:documented.meth
      ?summary:documented.summary
      ?tags:documented.tags
      ?deprecated:documented.deprecated
      ?operation_id:documented.operation_id
      ?description:documented.description
      ?decode_error:documented.decode_error
      ~request
      ~path:documented.path
      ~responses
      handler
  ;;

  let handle_in_group handler ready =
    let { requested = { documented; request }; responses } = ready in
    Group.Contextual_route
      (fun context ->
        make_route
          ~context
          ~invoke:(fun handler context body -> handler context body)
          ~meth:documented.meth
          ?summary:documented.summary
          ?tags:documented.tags
          ?deprecated:documented.deprecated
          ?operation_id:documented.operation_id
          ?description:documented.description
          ?decode_error:documented.decode_error
          ~request
          ~path:documented.path
          ~responses
          handler)
  ;;

  let ( ==> ) ready handler = handle_in_group handler ready
end
