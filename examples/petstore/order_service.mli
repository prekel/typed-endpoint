open! Base

(** In-memory service for the store-order aggregate. The service owns order
    identity and exposes domain values only. *)

type t

(** A requested order does not exist. *)
type error = [ `Not_found of int ]

(** An explicit order ID is already occupied. *)
type place_error = [ `Already_exists of int ]

(** Creates an isolated empty order store. *)
val create : unit -> t

(** Places an order, allocating an ID when [id] is absent. Explicit occupied
    IDs are rejected rather than overwritten. *)
val place
  :  t
  -> ?id:int
  -> Domain.Order.attributes
  -> (Domain.Order.t, place_error) Result.t

(** Finds an order by its assigned ID. *)
val find : t -> int -> Domain.Order.t option

(** Deletes an order or reports its missing ID. *)
val delete : t -> int -> (unit, error) Result.t
