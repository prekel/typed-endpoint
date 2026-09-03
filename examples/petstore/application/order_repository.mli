open! Base

(** Persistence port required by the order application service. *)
module type S = sig
  (** Effect used by the storage adapter. *)
  type 'a io

  (** Repository instance, commonly containing a connection pool. *)
  type t

  (** Errors from operations targeting an existing order. *)
  type error =
    [ `Not_found of int
    | `Persistence of Persistence_error.t
    ]

  (** Errors from insertion with an optional caller-provided ID. *)
  type place_error =
    [ `Already_exists of int
    | `Persistence of Persistence_error.t
    ]

  (** Stores an order and allocates its ID when absent. *)
  val place
    :  t
    -> ?id:int
    -> Domain.Order.attributes
    -> (Domain.Order.t, place_error) Result.t io

  (** Finds an order without treating absence as an infrastructure failure. *)
  val find : t -> int -> (Domain.Order.t option, Persistence_error.t) Result.t io

  (** Deletes one existing order. *)
  val delete : t -> int -> (unit, error) Result.t io
end
