open! Base

module type S = sig
  type 'a io
  type t

  val add
    :  t
    -> ?id:int
    -> Domain.Pet.attributes
    -> ( Domain.Pet.t
         , [ `Already_exists of int | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val update
    :  t
    -> id:int
    -> Domain.Pet.attributes
    -> ( Domain.Pet.t
         , [ `Not_found of int | `Persistence of Persistence_error.t ] )
         Result.t
         io

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
    -> ( int
         , [ `Not_found of int | `Empty_file | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val delete
    :  t
    -> int
    -> (unit, [ `Not_found of int | `Persistence of Persistence_error.t ]) Result.t io
end

module Make (Io : Base.Monad.S) (Repository : Pet_repository.S with type 'a io = 'a Io.t) =
struct
  type 'a io = 'a Io.t
  type t = { repository : Repository.t }

  let create ~repository = { repository }
  let add t = Repository.add t.repository
  let update t = Repository.update t.repository
  let patch t = Repository.patch t.repository
  let list_by_status t = Repository.list_by_status t.repository
  let list_by_tags t = Repository.list_by_tags t.repository
  let find_by_status t = Repository.find_by_status t.repository
  let find t = Repository.find t.repository
  let inventory t = Repository.inventory t.repository
  let upload_image t = Repository.upload_image t.repository
  let delete t = Repository.delete t.repository
end
