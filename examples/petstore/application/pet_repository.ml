open! Base

module type S = sig
  type 'a io
  type t

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

  val add : t -> ?id:int -> Domain.Pet.attributes -> (Domain.Pet.t, add_error) Result.t io
  val update : t -> id:int -> Domain.Pet.attributes -> (Domain.Pet.t, error) Result.t io

  val patch
    :  t
    -> id:int
    -> ?name:string
    -> ?status:Domain.Status.t
    -> unit
    -> (Domain.Pet.t, error) Result.t io

  val list_by_status
    :  t
    -> status:Domain.Status.t
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  val list_by_tags
    :  t
    -> tags:string list
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  val find_by_status
    :  t
    -> status:Domain.Status.t
    -> pagination:Domain.Page_request.t
    -> (Domain.Pet.t Domain.Page.t, Persistence_error.t) Result.t io

  val find : t -> int -> (Domain.Pet.t option, Persistence_error.t) Result.t io
  val inventory : t -> ((Domain.Status.t * int) list, Persistence_error.t) Result.t io

  val upload_image
    :  t
    -> id:int
    -> metadata:string option
    -> bytes:string
    -> (int, upload_error) Result.t io

  val delete : t -> int -> (unit, error) Result.t io
end
