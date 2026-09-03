open! Base

(** In-memory Petstore domain service.

    The service owns pet identity and returns domain values only. HTTP status
    selection and JSON conversion belong to the calling route. *)

type t

(** Domain error returned when a requested pet does not exist. *)
type error = [ `Not_found of int ]

(** Domain error returned when a requested explicit ID is already occupied. *)
type add_error = [ `Already_exists of int ]

(** Domain errors produced while attaching an image to a pet. *)
type upload_error =
  [ `Not_found of int
  | `Empty_file
  ]

(** Creates an isolated empty store. *)
val create : unit -> t

(** Adds a pet and assigns an ID. [id] supports the optional ID accepted by the
    Swagger Petstore payload; generated IDs never reuse an occupied slot and an
    explicit occupied ID is rejected rather than overwritten. *)
val add : t -> ?id:int -> Domain.Pet.attributes -> (Domain.Pet.t, add_error) Result.t

(** Replaces the attributes of an existing pet. *)
val update : t -> id:int -> Domain.Pet.attributes -> (Domain.Pet.t, error) Result.t

(** Changes only the supplied form fields of an existing pet. *)
val patch
  :  t
  -> id:int
  -> ?name:string
  -> ?status:Domain.Status.t
  -> unit
  -> (Domain.Pet.t, error) Result.t

(** Returns all pets having [status], ordered by ID. *)
val list_by_status : t -> status:Domain.Status.t -> Domain.Pet.t list

(** Returns pets carrying at least one of [tags], ordered by ID. *)
val list_by_tags : t -> tags:string list -> Domain.Pet.t list

(** Returns a stable, ID-ordered page of pets having [status]. *)
val find_by_status
  :  t
  -> status:Domain.Status.t
  -> pagination:Domain.Page_request.t
  -> Domain.Pet.t Domain.Page.t

(** Finds one pet by its assigned ID. *)
val find : t -> int -> Domain.Pet.t option

(** Counts pets in each official lifecycle state. *)
val inventory : t -> (Domain.Status.t * int) list

(** Stores one opaque image payload for an existing pet and returns its byte
    length. Empty payloads are rejected. *)
val upload_image
  :  t
  -> id:int
  -> metadata:string option
  -> bytes:string
  -> (int, upload_error) Result.t

(** Deletes one pet or returns its missing ID. *)
val delete : t -> int -> (unit, error) Result.t
