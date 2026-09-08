open! Base

module type S = sig
  type 'a io
  type connection

  type error =
    [ `Not_found of int
    | `Persistence of Persistence_error.t
    ]

  type add_error =
    [ `Already_exists of int
    | `Persistence of Persistence_error.t
    ]

  type upload_error =
    [ error
    | `Empty_file
    ]

  val add
    :  conn:connection
    -> ?id:int
    -> Domain.Pet.attributes
    -> (Domain.Pet.t, add_error) Result.t io

  val update
    :  conn:connection
    -> id:int
    -> Domain.Pet.attributes
    -> (Domain.Pet.t, error) Result.t io

  val patch
    :  conn:connection
    -> id:int
    -> ?name:string
    -> ?status:Domain.Status.t
    -> unit
    -> (Domain.Pet.t, error) Result.t io

  val list_by_status
    :  conn:connection
    -> status:Domain.Status.t
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  val list_by_tags
    :  conn:connection
    -> tags:string list
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  val find_by_status
    :  conn:connection
    -> status:Domain.Status.t
    -> pagination:Domain.Page_request.t
    -> (Domain.Pet.t Domain.Page.t, Persistence_error.t) Result.t io

  val find
    :  conn:connection
    -> int
    -> (Domain.Pet.t option, Persistence_error.t) Result.t io

  val inventory
    :  conn:connection
    -> ((Domain.Status.t * int) list, Persistence_error.t) Result.t io

  val upload_image
    :  conn:connection
    -> id:int
    -> metadata:string option
    -> bytes:string
    -> (int, upload_error) Result.t io

  val delete : conn:connection -> int -> (unit, error) Result.t io
end
