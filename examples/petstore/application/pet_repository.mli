open! Base

(** Persistence port required by the pet application service. Implementations
    may use an identity effect for tests or [Lwt.t] for asynchronous storage. *)
module type S = sig
  (** Effect used by the storage adapter. *)
  type 'a io

  (** Repository instance, commonly containing a connection pool. *)
  type t

  (** Errors from operations targeting an existing pet. *)
  type error =
    [ `Not_found of int
    | `Persistence of Persistence_error.t
    ]

  (** Errors from insertion with an optional caller-provided ID. *)
  type add_error =
    [ `Already_exists of int
    | `Persistence of Persistence_error.t
    ]

  (** Errors from storing an image attachment. *)
  type upload_error =
    [ error
    | `Empty_file
    ]

  (** Inserts a pet, allowing the storage implementation to allocate its ID. *)
  val add : t -> ?id:int -> Domain.Pet.attributes -> (Domain.Pet.t, add_error) Result.t io

  (** Replaces one existing pet. *)
  val update : t -> id:int -> Domain.Pet.attributes -> (Domain.Pet.t, error) Result.t io

  (** Atomically changes the supplied subset of attributes. *)
  val patch
    :  t
    -> id:int
    -> ?name:string
    -> ?status:Domain.Status.t
    -> unit
    -> (Domain.Pet.t, error) Result.t io

  (** Returns an ID-ordered status selection. *)
  val list_by_status
    :  t
    -> status:Domain.Status.t
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  (** Returns pets carrying at least one requested tag. *)
  val list_by_tags
    :  t
    -> tags:string list
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  (** Performs bounded status pagination in the storage layer. *)
  val find_by_status
    :  t
    -> status:Domain.Status.t
    -> pagination:Domain.Page_request.t
    -> (Domain.Pet.t Domain.Page.t, Persistence_error.t) Result.t io

  (** Finds one pet without treating absence as an infrastructure failure. *)
  val find : t -> int -> (Domain.Pet.t option, Persistence_error.t) Result.t io

  (** Counts pets by lifecycle state. *)
  val inventory : t -> ((Domain.Status.t * int) list, Persistence_error.t) Result.t io

  (** Stores an opaque image for an existing pet. *)
  val upload_image
    :  t
    -> id:int
    -> metadata:string option
    -> bytes:string
    -> (int, upload_error) Result.t io

  (** Deletes one existing pet. *)
  val delete : t -> int -> (unit, error) Result.t io
end
