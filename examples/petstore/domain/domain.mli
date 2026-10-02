open! Base

(** Business types used by the Petstore application.

    This module deliberately contains no JSON or HTTP concerns. Transport
    adapters convert DTOs at the route boundary. *)

(** Lifecycle states shared by pet commands, filters, and inventory. *)
module Status : sig
  (** Lifecycle state of a pet. *)
  type t =
    | Available
    | Pending
    | Sold

  (** Structural equality for status filtering and tests. *)
  val equal : t -> t -> bool
end

(** Domain category value attached to a pet. *)
module Category : sig
  (** Optional category attributes associated with a pet. *)
  type t =
    { id : int option
    ; name : string option
    }
end

(** Domain tag value attached to a pet. *)
module Tag : sig
  (** Optional tag attributes associated with a pet. *)
  type t =
    { id : int option
    ; name : string option
    }
end

(** Pet aggregate values and mutable business attributes. *)
module Pet : sig
  (** Editable business attributes supplied when a pet is created or updated.
      Identity is intentionally kept outside this type so the service owns ID
      allocation. *)
  type attributes =
    { name : string
    ; category : Category.t option
    ; photo_urls : string list
    ; tags : Tag.t list option
    ; status : Status.t option
    }

  (** A stored pet with an assigned identity. *)
  type t =
    { id : int
    ; attributes : attributes
    }
end

(** Order values and order-specific lifecycle states. *)
module Order : sig
  (** Lifecycle state of a store order. *)
  module Status : sig
    (** State transitions supported by the store order workflow. *)
    type t =
      | Placed
      | Approved
      | Delivered

    (** Structural equality for order-state comparisons. *)
    val equal : t -> t -> bool
  end

  (** Business attributes of an order. Identity is allocated by the order
      service when the request omits it. *)
  type attributes =
    { pet_id : int option
    ; quantity : int option
    ; ship_date : string option
    ; status : Status.t option
    ; complete : bool option
    }

  (** A stored order with an assigned identity. *)
  type t =
    { id : int
    ; attributes : attributes
    }
end

(** User profile values keyed by username. *)
module User : sig
  (** Editable user profile and credentials. The username is kept outside this
      record because it is the service-level identity. *)
  type attributes =
    { id : int option
    ; first_name : string option
    ; last_name : string option
    ; email : string option
    ; password : string option
    ; phone : string option
    ; user_status : int option
    }

  (** A stored user identified by a non-empty username. *)
  type t =
    { username : string
    ; attributes : attributes
    }
end

(** Validated, bounded pagination input. *)
module Page_request : sig
  (** Validated pagination input. Pages are one-based; limits are capped to
      protect the service from accidentally unbounded collection reads. *)
  type t

  (** Default page number used when the query parameter is absent. *)
  val default_page : int

  (** Default page size used when the query parameter is absent. *)
  val default_limit : int

  (** Largest accepted page number. *)
  val max_page : int

  (** Largest accepted page size. *)
  val max_limit : int

  (** Creates a pagination request or explains which bound is invalid. *)
  val create : page:int -> limit:int -> (t, string) Result.t

  (** Returns the validated one-based page number. *)
  val page : t -> int

  (** Returns the validated maximum number of items in a page. *)
  val limit : t -> int
end

(** Result of applying a validated page request to a collection. *)
module Page : sig
  (** One deterministic page of domain values. *)
  type 'a t =
    { items : 'a list
    ; page : int
    ; limit : int
    ; total : int
    ; total_pages : int
    }
end
