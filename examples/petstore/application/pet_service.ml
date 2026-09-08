open! Base

module type S = sig
  type 'a io
  type database

  val add
    :  database:database
    -> ?id:int
    -> Domain.Pet.attributes
    -> ( Domain.Pet.t
         , [ `Already_exists of int | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val update
    :  database:database
    -> id:int
    -> Domain.Pet.attributes
    -> ( Domain.Pet.t
         , [ `Not_found of int | `Persistence of Persistence_error.t ] )
         Result.t
         io

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

  val list_by_status
    :  database:database
    -> status:Domain.Status.t
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  val list_by_tags
    :  database:database
    -> tags:string list
    -> (Domain.Pet.t list, Persistence_error.t) Result.t io

  val find_by_status
    :  database:database
    -> status:Domain.Status.t
    -> pagination:Domain.Page_request.t
    -> (Domain.Pet.t Domain.Page.t, Persistence_error.t) Result.t io

  val find
    :  database:database
    -> int
    -> (Domain.Pet.t option, Persistence_error.t) Result.t io

  val inventory
    :  database:database
    -> ((Domain.Status.t * int) list, Persistence_error.t) Result.t io

  val upload_image
    :  database:database
    -> id:int
    -> metadata:string option
    -> bytes:string
    -> ( int
         , [ `Not_found of int | `Empty_file | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val delete
    :  database:database
    -> int
    -> (unit, [ `Not_found of int | `Persistence of Persistence_error.t ]) Result.t io
end

module Make
    (Io : Base.Monad.S)
    (Database : Database.S with type 'a io = 'a Io.t)
    (Repository :
       Pet_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection) =
struct
  type 'a io = 'a Io.t
  type database = Database.t

  let persistence error = `Persistence error

  let add ~database ?id attributes =
    Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
      Repository.add ~conn ?id attributes)
  ;;

  let update ~database ~id attributes =
    Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
      Repository.update ~conn ~id attributes)
  ;;

  let patch ~database ~id ?name ?status () =
    Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
      Repository.patch ~conn ~id ?name ?status ())
  ;;

  let list_by_status ~database ~status =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Repository.list_by_status ~conn ~status)
  ;;

  let list_by_tags ~database ~tags =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Repository.list_by_tags ~conn ~tags)
  ;;

  let find_by_status ~database ~status ~pagination =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Repository.find_by_status ~conn ~status ~pagination)
  ;;

  let find ~database id =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Repository.find ~conn id)
  ;;

  let inventory ~database =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Repository.inventory ~conn)
  ;;

  let upload_image ~database ~id ~metadata ~bytes =
    Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
      Repository.upload_image ~conn ~id ~metadata ~bytes)
  ;;

  let delete ~database id =
    Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
      Repository.delete ~conn id)
  ;;
end
