open! Base

module Documentation : sig
  type t =
    { description : string
    ; tags : string list
    }

  val v : ?tags:string list -> description:string -> unit -> t
end

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

type param_kind =
  [ `Path
  | `Query
  ]

type param =
  { name : string
  ; kind : param_kind
  ; required : bool
  ; schema : Ppx_deriving_jsonschema_runtime.t
  ; metadata : Documentation.t
  }

type request_body =
  | No_body
  | Json_body of
      { schema : Ppx_deriving_jsonschema_runtime.t
      ; metadata : Documentation.t
      }
  | Text_body of { metadata : Documentation.t }

type response_content =
  | Text
  | Json of Ppx_deriving_jsonschema_runtime.t

type response_payload =
  { metadata : Documentation.t
  ; content : response_content list
  }

type response =
  { status : int
  ; payload : response_payload
  }

type endpoint =
  { meth : string
  ; path : string
  ; metadata : Operation_metadata.t option
  ; params : param list
  ; request_body : request_body
  ; responses : response list
  ; parse_error_response : response option
  ; context_responses : response list
  ; response_families : int list list
  ; has_parsers : bool
  }

type route =
  { meth : string
  ; path : string
  ; endpoint : endpoint option
  }

type group =
  { prefix : string list
  ; metadata : Operation_metadata.t
  ; routes : route list
  }

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
    | Missing_parse_error_policy of
        { meth : string
        ; path : string
        }

  val to_string : t -> string
end

module Compiled : sig
  type compiled_route =
    { meth : string
    ; path : string
    ; endpoint : endpoint option
    }

  type compiled_group =
    { metadata : Operation_metadata.t
    ; routes : compiled_route list
    }

  type t

  val groups : t -> compiled_group list
end

val prefix_to_string : string list -> string
val compile : group list -> (Compiled.t, Compile_error.t list) Result.t
val compile_exn : group list -> Compiled.t
