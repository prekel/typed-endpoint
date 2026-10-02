open! Base
open Typed_endpoint

(** Wire codecs for the Petstore lifecycle-status enum. *)
module Status : sig
  (** Maps the public lowercase status representation to the domain enum. *)
  type t = Domain.Status.t

  (** Parses and documents status path and query parameters. *)
  include Parameter.S with type t := t

  (** Encodes the domain status for JSON responses. *)
  val to_string : t -> string
end

(** JSON codec and domain conversion for pet categories. *)
module Category : sig
  (** JSON representation of a Petstore category. *)
  type t =
    { id : int option
    ; name : string option
    }

  (** JSON decoder, encoder, and schema for this wire record. *)
  include Json_payload.S with type t := t

  (** Removes transport-specific representation details. *)
  val to_domain : t -> Domain.Category.t

  (** Converts domain data to its public JSON representation. *)
  val of_domain : Domain.Category.t -> t
end

(** JSON codec and domain conversion for pet tags. *)
module Tag : sig
  (** JSON representation of a Petstore tag. *)
  type t =
    { id : int option
    ; name : string option
    }

  (** JSON decoder, encoder, and schema for this wire record. *)
  include Json_payload.S with type t := t

  (** Removes transport-specific representation details. *)
  val to_domain : t -> Domain.Tag.t

  (** Converts domain data to its public JSON representation. *)
  val of_domain : Domain.Tag.t -> t
end

(** Pet request and response DTO codec with domain conversions. *)
module Pet : sig
  (** Petstore-compatible request and response body. The optional [id] is
      positive when present and preserved on input, while responses produced
      from a domain pet always contain an assigned ID. *)
  type t =
    { id : int option
    ; name : string
    ; category : Category.t option
    ; photo_urls : string list
    ; tags : Tag.t list option
    ; status : string option
    }

  (** JSON decoder, encoder, and schema for the Petstore pet representation. *)
  include Json_payload.S with type t := t

  (** Converts the wire representation to an optional requested ID and domain
      attributes. The conversion remains fallible for DTO values constructed
      directly rather than decoded from JSON. *)
  val to_domain : t -> (int option * Domain.Pet.attributes, string) Result.t

  (** Converts a stored domain pet to the Petstore wire shape. *)
  val of_domain : Domain.Pet.t -> t
end

(** Query-parameter codec for a comma-separated list of pet tags. *)
module Tags : sig
  (** A non-empty comma-separated list used by [findPetsByTags]. *)
  type t = string list

  (** Parses the repeated or comma-separated tag query representation. *)
  include Parameter.S with type t := t
end

(** Encoder and schema for the official pet collection response. *)
module Pet_list : sig
  (** Official collection response used by status and tag searches. *)
  type t = Pet.t list

  (** JSON encoder and response schema. *)
  include Response_payload.S with type t := t

  (** Converts an ID-ordered domain collection to the official JSON array. *)
  val of_domain : Domain.Pet.t list -> t
end

(** Encoder and schema for pagination metadata. *)
module Pagination : sig
  (** Metadata included with every paginated collection response. *)
  type t =
    { page : int
    ; limit : int
    ; total : int
    ; total_pages : int
    }

  (** JSON encoder and response schema. *)
  include Response_payload.S with type t := t

  (** Extracts pagination metadata independently of the item type. *)
  val of_domain : 'a Domain.Page.t -> t
end

(** Encoder and schema for the paginated pet-search response. *)
module Pet_page : sig
  (** Paginated response for the typed-endpoint search extension. *)
  type t =
    { items : Pet.t list
    ; pagination : Pagination.t
    }

  (** JSON encoder and response schema. *)
  include Response_payload.S with type t := t

  (** Converts a domain page and every contained pet to its wire shape. *)
  val of_domain : Domain.Pet.t Domain.Page.t -> t
end

(** Encoder and schema for status-to-quantity inventory data. *)
module Inventory : sig
  (** Map from official pet status names to current quantities. *)
  type t = (string * int) list

  (** JSON encoder and response schema. *)
  include Response_payload.S with type t := t

  (** Converts typed domain statuses to their lowercase object keys. *)
  val of_domain : (Domain.Status.t * int) list -> t
end

(** JSON codec and domain conversion for store orders. *)
module Order : sig
  (** Swagger Petstore order representation. *)
  type t =
    { id : int option
    ; pet_id : int option
    ; quantity : int option
    ; ship_date : string option
    ; status : string option
    ; complete : bool option
    }

  (** JSON decoder, encoder, and schema for this wire record. *)
  include Json_payload.S with type t := t

  (** Validates the wire representation and separates an optional requested ID
      from domain attributes. *)
  val to_domain : t -> (int option * Domain.Order.attributes, string) Result.t

  (** Converts a stored order to the official camelCase wire shape. *)
  val of_domain : Domain.Order.t -> t
end

(** JSON codec and domain conversion for Petstore users. *)
module User : sig
  (** Swagger Petstore user representation. All wire fields are optional, but
      creation requires a non-empty username. *)
  type t =
    { id : int option
    ; username : string option
    ; first_name : string option
    ; last_name : string option
    ; email : string option
    ; password : string option
    ; phone : string option
    ; user_status : int option
    }

  (** JSON decoder, encoder, and schema for this wire record. *)
  include Json_payload.S with type t := t

  (** Converts a request DTO to a domain user. The optional [username] argument
      is the authoritative identity from a path parameter during updates. *)
  val to_domain : ?username:string -> t -> (Domain.User.t, string) Result.t

  (** Converts a domain user profile to the official camelCase wire shape. *)
  val of_domain : Domain.User.t -> t
end

(** JSON codec for a batch of user-creation requests. *)
module User_list : sig
  (** JSON request body accepted by [createUsersWithListInput]. *)
  type t = User.t list

  (** JSON decoder, encoder, and schema for the list. *)
  include Json_payload.S with type t := t

  (** Validates every user and preserves request order. *)
  val to_domain : t -> (Domain.User.t list, string) Result.t
end

(** Encoder and schema for the login response. *)
module Login_token : sig
  (** JSON string returned by the official login operation. *)
  type t = string

  (** JSON encoder and response schema. *)
  include Response_payload.S with type t := t
end

(** Error and upload-result DTOs used by the HTTP controllers. *)
module Api_response : sig
  (** Petstore-compatible error body. [code] mirrors the selected HTTP status. *)
  type t =
    { code : int
    ; type_ : string
    ; message : string
    }

  (** JSON encoder and response schema. *)
  include Response_payload.S with type t := t

  (** Maps framework-independent request decoding failures to the public error
      representation. The runtime chooses the corresponding HTTP status. *)
  val of_decode_error : Decode_error.t -> t

  (** Builds the public 404 representation for [id]. *)
  val not_found : int -> t

  (** Builds the public 409 representation for an occupied explicit [id]. *)
  val conflict : int -> t

  (** Builds the public 400 representation for an invalid command. *)
  val bad_request : string -> t

  (** Builds a sanitized 503 representation. Internal failure details are not
      exposed to the HTTP client. *)
  val persistence_error : Persistence_error.t -> t

  (** Builds the public missing-order representation. *)
  val order_not_found : int -> t

  (** Builds the public missing-user representation. *)
  val user_not_found : string -> t

  (** Builds a conflict response for an occupied username. *)
  val user_conflict : string -> t

  (** Builds a successful upload response. *)
  val upload_success : id:int -> bytes:int -> metadata:string option -> t
end
