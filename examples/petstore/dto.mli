open! Base
open Typed_endpoint

module Category : sig
  type t =
    { id : int option
    ; name : string option
    }

  include Request_payload.S with type t := t
  include Response_payload.S with type t := t
end

module Tag : sig
  type t =
    { id : int option
    ; name : string option
    }

  include Request_payload.S with type t := t
  include Response_payload.S with type t := t
end

module Pet : sig
  type t =
    { id : int option
    ; name : string
    ; category : Category.t option
    ; photo_urls : string list
    ; tags : Tag.t list option
    ; status : string option
    }

  include Request_payload.S with type t := t
  include Response_payload.S with type t := t
end

module Pet_list : sig
  type t = Pet.t list

  include Response_payload.S with type t := t
end

module Api_response : sig
  type t =
    { code : int
    ; type_ : string
    ; message : string
    }

  include Response_payload.S with type t := t

  val of_decode_error : Decode_error.t -> t
  val not_found : int -> t
end
