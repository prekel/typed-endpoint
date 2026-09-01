open! Base

module type Metadata = sig
  type t

  val description : t -> string
  val summary : t -> string option
  val tags : t -> string list
  val deprecated : t -> bool
  val operation_id : t -> string option
end

module Make (Metadata : Metadata) : sig
  type param_kind =
    [ `Path
    | `Query
    ]

  type param_spec =
    { name : string
    ; kind : param_kind
    ; required : bool
    ; schema : Ppx_deriving_jsonschema_runtime.t
    ; meta : Metadata.t
    }

  type request_body_spec =
    | No_body
    | Json_body of
        { schema : Ppx_deriving_jsonschema_runtime.t
        ; meta : Metadata.t
        }
    | Text_body of { meta : Metadata.t }

  type response_payload_spec =
    | Resp_empty of { meta : Metadata.t }
    | Resp_text of { meta : Metadata.t }
    | Resp_json of
        { schema : Ppx_deriving_jsonschema_runtime.t
        ; meta : Metadata.t
        }

  type response_spec =
    { status : int
    ; payload : response_payload_spec
    }

  type endpoint =
    { meth : string
    ; path : string
    ; operation_meta : Metadata.t option
    ; params : param_spec list
    ; request_body : request_body_spec
    ; responses : response_spec list
    }

  type group =
    { group_meta : Metadata.t
    ; prefix : string list
    ; endpoints : endpoint list
    }

  val prefix_to_string : string list -> string
  val render : ?title:string -> ?version:string -> group list -> Yojson.Safe.t
end
