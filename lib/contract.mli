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

module Schema : sig
  type t =
    { value : Ppx_deriving_jsonschema_runtime.t
    ; name : string option
    }

  val v : ?name:string -> Ppx_deriving_jsonschema_runtime.t -> t
  val equal : t -> t -> bool
end

module Security : sig
  module Scheme : sig
    type api_key_location =
      [ `Header
      | `Query
      | `Cookie
      ]

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

    type t =
      { name : string
      ; description : string
      ; kind : kind
      }

    val api_key
      :  name:string
      -> parameter:string
      -> location:api_key_location
      -> description:string
      -> unit
      -> t

    val http_bearer
      :  name:string
      -> ?bearer_format:string
      -> description:string
      -> unit
      -> t

    val oauth2_implicit
      :  name:string
      -> authorization_url:string
      -> scopes:(string * string) list
      -> description:string
      -> unit
      -> t

    val equal : t -> t -> bool
  end

  type requirement = (Scheme.t * string list) list

  val require : ?scopes:string list -> Scheme.t -> requirement
  val all : requirement list -> requirement
  val combine_alternatives : requirement list -> requirement list -> requirement list
end

module Openapi : sig
  module Server : sig
    type t =
      { url : string
      ; description : string option
      }

    val v : url:string -> ?description:string -> unit -> t
  end

  module Config : sig
    type t =
      { title : string
      ; version : string
      ; description : string option
      ; servers : Server.t list
      }

    val v
      :  title:string
      -> version:string
      -> ?description:string
      -> ?servers:Server.t list
      -> unit
      -> t

    val default : t
  end
end

type param_kind =
  [ `Path
  | `Query
  ]

type param =
  { name : string
  ; kind : param_kind
  ; required : bool
  ; schema : Schema.t
  ; metadata : Documentation.t
  }

type request_body =
  | No_body
  | Json_body of
      { schema : Schema.t
      ; metadata : Documentation.t
      ; max_body_bytes : int
      }
  | Text_body of
      { metadata : Documentation.t
      ; max_body_bytes : int
      }

type response_content =
  | Text
  | Json of Schema.t list

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
  ; decode_error_responses : response list
  ; context_responses : response list
  ; security : Security.requirement list
  ; response_families : int list list
  ; has_decoders : bool
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
  val schemas : t -> Schema.t list
  val security_schemes : t -> Security.Scheme.t list
end

val prefix_to_string : string list -> string
val compile : group list -> (Compiled.t, Compile_error.t list) Result.t
val compile_exn : group list -> Compiled.t
