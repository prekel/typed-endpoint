open! Base

(** In-memory user service keyed by the domain username. Bulk creation is
    atomic: a duplicate leaves the store unchanged. *)

type t

(** A requested username does not exist. *)
type error = [ `Not_found of string ]

(** A requested username is already occupied. *)
type create_error = [ `Already_exists of string ]

(** Creates an isolated empty user store. *)
val create : unit -> t

(** Adds one user without replacing an existing username. *)
val add : t -> Domain.User.t -> (Domain.User.t, create_error) Result.t

(** Adds all users atomically. Duplicate usernames in either the request or the
    store reject the complete batch. *)
val add_many : t -> Domain.User.t list -> (Domain.User.t list, create_error) Result.t

(** Finds one user by username. *)
val find : t -> string -> Domain.User.t option

(** Replaces an existing user selected by [username]. *)
val update : t -> username:string -> Domain.User.t -> (Domain.User.t, error) Result.t

(** Deletes an existing user. *)
val delete : t -> string -> (unit, error) Result.t

(** Checks the clear-text demo credential used by the official login route.
    A production service would delegate this operation to a password hasher and
    session provider. *)
val authenticate : t -> username:string -> password:string -> bool
