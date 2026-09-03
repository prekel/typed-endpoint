open! Base

(** Persistence port required by the user application service. *)
module type S = sig
  (** Effect used by the storage adapter. *)
  type 'a io

  (** Repository instance, commonly containing a connection pool. *)
  type t

  (** Errors from operations targeting an existing user. *)
  type error =
    [ `Not_found of string
    | `Persistence of Persistence_error.t
    ]

  (** Errors from inserting one or more users. *)
  type create_error =
    [ `Already_exists of string
    | `Persistence of Persistence_error.t
    ]

  (** Inserts one user without replacing an occupied username. *)
  val add : t -> Domain.User.t -> (Domain.User.t, create_error) Result.t io

  (** Inserts a complete batch atomically. *)
  val add_many : t -> Domain.User.t list -> (Domain.User.t list, create_error) Result.t io

  (** Finds one user by username. *)
  val find : t -> string -> (Domain.User.t option, Persistence_error.t) Result.t io

  (** Replaces the user selected by the authoritative path username. *)
  val update : t -> username:string -> Domain.User.t -> (Domain.User.t, error) Result.t io

  (** Deletes one existing user. *)
  val delete : t -> string -> (unit, error) Result.t io

  (** Checks the stored demo credential. *)
  val authenticate
    :  t
    -> username:string
    -> password:string
    -> (bool, Persistence_error.t) Result.t io
end
