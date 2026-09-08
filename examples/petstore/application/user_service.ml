open! Base

module type S = sig
  type 'a io
  type database

  val add
    :  database:database
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Already_exists of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val add_many
    :  database:database
    -> Domain.User.t list
    -> ( Domain.User.t list
         , [ `Already_exists of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val find
    :  database:database
    -> string
    -> (Domain.User.t option, Persistence_error.t) Result.t io

  val update
    :  database:database
    -> username:string
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Not_found of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val delete
    :  database:database
    -> string
    -> (unit, [ `Not_found of string | `Persistence of Persistence_error.t ]) Result.t io

  val authenticate
    :  database:database
    -> username:string
    -> password:string
    -> (bool, Persistence_error.t) Result.t io
end

module Make
    (Io : Base.Monad.S)
    (Database : Database.S with type 'a io = 'a Io.t)
    (Repository :
       User_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection) =
struct
  type 'a io = 'a Io.t
  type database = Database.t

  let persistence error = `Persistence error

  let add ~database user =
    Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
      Repository.add ~conn user)
  ;;

  let add_many ~database users =
    Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
      Repository.add_many ~conn users)
  ;;

  let find ~database username =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Repository.find ~conn username)
  ;;

  let update ~database ~username user =
    Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
      Repository.update ~conn ~username user)
  ;;

  let delete ~database username =
    Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
      Repository.delete ~conn username)
  ;;

  let authenticate ~database ~username ~password =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Repository.authenticate ~conn ~username ~password)
  ;;
end
