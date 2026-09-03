open! Base

(** Typed application dependency container. Its parameters preserve the exact
    service implementations, so consumers cannot accidentally receive a
    service from another composition root. *)
type ('pets, 'orders, 'users) t

(** Assembles already-created services. Construction is intentionally explicit
    and happens once at the executable boundary. *)
val v : pets:'pets -> orders:'orders -> users:'users -> ('pets, 'orders, 'users) t

(** Returns the pet service while preserving its concrete type. *)
val pets : ('pets, _, _) t -> 'pets

(** Returns the order service while preserving its concrete type. *)
val orders : (_, 'orders, _) t -> 'orders

(** Returns the user service while preserving its concrete type. *)
val users : (_, _, 'users) t -> 'users
