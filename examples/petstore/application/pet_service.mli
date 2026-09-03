open! Base

(** Application service for the pet aggregate. It exposes domain values and an
    abstract effect, and is independent of HTTP DTOs and storage technology. *)
module type S = sig
  (** Effect shared with the injected repository. *)
  type 'a io

  (** Pet service instance. *)
  type t

  (** Adds a pet and lets the repository allocate an ID when absent. *)
  val add
    :  t
    -> ?id:int
    -> Domain.Pet.attributes
    -> ( Domain.Pet.t
         , [ `Already_exists of int | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Replaces an existing pet. *)
  val update
    :  t
    -> id:int
    -> Domain.Pet.attributes
    -> ( Domain.Pet.t
         , [ `Not_found of int | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Atomically changes the supplied subset of attributes. *)
  val patch
    :  t
    -> id:int
    -> ?name:string
    -> ?status:Domain.Status.t
    -> unit
    -> ( Domain.Pet.t
         , [ `Not_found of int | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Returns all pets in an official lifecycle state. *)
  val list_by_status
    :  t
    -> status:Domain.Status.t
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  (** Returns pets carrying at least one requested tag. *)
  val list_by_tags
    :  t
    -> tags:string list
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  (** Returns a bounded, stable page selected by status. *)
  val find_by_status
    :  t
    -> status:Domain.Status.t
    -> pagination:Domain.Page_request.t
    -> (Domain.Pet.t Domain.Page.t, Persistence_error.t) Result.t io

  (** Finds one pet; absence is not a persistence error. *)
  val find : t -> int -> (Domain.Pet.t option, Persistence_error.t) Result.t io

  (** Counts pets in each official lifecycle state. *)
  val inventory : t -> ((Domain.Status.t * int) list, Persistence_error.t) Result.t io

  (** Attaches one opaque image to an existing pet. *)
  val upload_image
    :  t
    -> id:int
    -> metadata:string option
    -> bytes:string
    -> ( int
         , [ `Not_found of int | `Empty_file | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Deletes one existing pet. *)
  val delete
    :  t
    -> int
    -> (unit, [ `Not_found of int | `Persistence of Persistence_error.t ]) Result.t io
end

(** Injects a repository implementation into the pet application service. *)
module Make
    (Io : Base.Monad.S)
    (Repository : Pet_repository.S with type 'a io = 'a Io.t) : sig
  include S with type 'a io = 'a Io.t

  (** Creates a pet service using the supplied repository instance. *)
  val create : repository:Repository.t -> t
end
