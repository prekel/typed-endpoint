open! Base

(** Persistence port required by the order application service. *)
module type S = sig
  (** Effect used by the storage adapter. *)
  type 'a io

  (** Connection supplied by the application transaction boundary. *)
  type connection

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
    :  conn:connection
    -> ?id:int
    -> Domain.Order.attributes
    -> (Domain.Order.t, place_error) Result.t io

  (** Finds an order without treating absence as an infrastructure failure. *)
  val find
    :  conn:connection
    -> int
    -> (Domain.Order.t option, Persistence_error.t) Result.t io

  (** Deletes one existing order. *)
  val delete : conn:connection -> int -> (unit, error) Result.t io
end
