open! Base

(** Stateless application service for the pet aggregate. It owns transaction
    boundaries and exposes only domain values, never HTTP DTOs. *)
module type S = sig
  (** Effect shared by the database and repository. *)
  type 'a io

  (** Runtime database resource supplied at the application boundary. *)
  type database

  (** Adds a pet in one transaction and allocates an ID when absent. *)
  val add
    :  database:database
    -> ?id:int
    -> Domain.Pet.attributes
    -> ( Domain.Pet.t
         , [ `Already_exists of int | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Replaces an existing pet in one transaction. *)
  val update
    :  database:database
    -> id:int
    -> Domain.Pet.attributes
    -> ( Domain.Pet.t
         , [ `Not_found of int | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Atomically changes the supplied subset of attributes. *)
  val patch
    :  database:database
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
    :  database:database
    -> status:Domain.Status.t
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  (** Returns pets carrying at least one requested tag. *)
  val list_by_tags
    :  database:database
    -> tags:string list
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  (** Returns a bounded, stable page selected by status. *)
  val find_by_status
    :  database:database
    -> status:Domain.Status.t
    -> pagination:Domain.Page_request.t
    -> (Domain.Pet.t Domain.Page.t, Persistence_error.t) Result.t io

  (** Finds one pet; absence is not a persistence error. *)
  val find
    :  database:database
    -> int
    -> (Domain.Pet.t option, Persistence_error.t) Result.t io

  (** Counts pets in each official lifecycle state. *)
  val inventory
    :  database:database
    -> ((Domain.Status.t * int) list, Persistence_error.t) Result.t io

  (** Attaches one opaque image to an existing pet in one transaction. *)
  val upload_image
    :  database:database
    -> id:int
    -> metadata:string option
    -> bytes:string
    -> ( int
         , [ `Not_found of int | `Empty_file | `Persistence of Persistence_error.t ] )
         Result.t
         io

  (** Deletes one existing pet in one transaction. *)
  val delete
    :  database:database
    -> int
    -> (unit, [ `Not_found of int | `Persistence of Persistence_error.t ]) Result.t io
end

(** Injects the database algebra and repository implementation at compile
    time. The resulting module is stateless. *)
module Make
    (Io : Base.Monad.S)
    (Database : Database.S with type 'a io = 'a Io.t)
    (_ :
       Pet_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection) :
  S with type 'a io = 'a Io.t and type database = Database.t
