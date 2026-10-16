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
    -> actor:Domain.User.actor
    -> Domain.User.t list
    -> ( Domain.User.t list
         , [ `Forbidden
           | `Already_exists of string
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         io

  val find
    :  database:database
    -> string
    -> (Domain.User.t option, Persistence_error.t) Result.t io

  val update
    :  database:database
    -> actor:Domain.User.actor
    -> username:string
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Forbidden | `Not_found of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val delete
    :  database:database
    -> actor:Domain.User.actor
    -> string
    -> ( unit
         , [ `Forbidden | `Not_found of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

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
        and type connection = Database.connection)
    (Sessions :
       Session_repository.S
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

  let add_many ~database ~actor users =
    match actor with
    | Domain.User.Session_user _ -> Io.return (Error `Forbidden)
    | Administrator ->
      Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
        let open Io.Let_syntax in
        let%map result = Repository.add_many ~conn users in
        Result.map_error result ~f:(function
          | `Already_exists username -> `Already_exists username
          | `Persistence error -> `Persistence error))
  ;;

  let find ~database username =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Repository.find ~conn username)
  ;;

  let permitted actor username =
    match actor with
    | Domain.User.Administrator -> true
    | Session_user subject -> String.equal subject username
  ;;

  let update ~database ~actor ~username user =
    if not (permitted actor username) then
      Io.return (Error `Forbidden)
    else
      Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
        let open Io.Let_syntax in
        let%bind existing = Repository.find ~conn username in
        match existing with
        | Error error -> Io.return (Error (`Persistence error))
        | Ok None -> Io.return (Error (`Not_found username))
        | Ok (Some existing) ->
          let%bind updated = Repository.update ~conn ~username user in
          (match updated with
           | Error (`Not_found username) -> Io.return (Error (`Not_found username))
           | Error (`Persistence error) -> Io.return (Error (`Persistence error))
           | Ok updated ->
             if
               Option.equal
                 String.equal
                 existing.attributes.password
                 updated.attributes.password
             then
               Io.return (Ok updated)
             else (
               let%map revoked = Sessions.remove_by_username ~conn ~username in
               revoked
               |> Result.map ~f:(fun () -> updated)
               |> Result.map_error ~f:persistence)))
  ;;

  let delete ~database ~actor username =
    if not (permitted actor username) then
      Io.return (Error `Forbidden)
    else
      Database.transaction database ~on_error:persistence ~f:(fun ~conn ->
        let open Io.Let_syntax in
        let%bind removed = Repository.delete ~conn username in
        match removed with
        | Error (`Not_found username) -> Io.return (Error (`Not_found username))
        | Error (`Persistence error) -> Io.return (Error (`Persistence error))
        | Ok () ->
          let%map revoked = Sessions.remove_by_username ~conn ~username in
          Result.map_error revoked ~f:persistence)
  ;;

  let authenticate ~database ~username ~password =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Repository.authenticate ~conn ~username ~password)
  ;;
end
