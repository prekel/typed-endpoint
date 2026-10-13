open! Base

(* Stateless session use cases; login and logout define transaction boundaries. *)
module type S = sig
  type 'a io
  type database

  val login
    :  database:database
    -> username:string
    -> password:string
    -> (Domain.Session.t option, Persistence_error.t) Result.t io

  (* Expired tokens never resolve to an identity. *)
  val find
    :  database:database
    -> string
    -> (Domain.Session.t option, Persistence_error.t) Result.t io

  val logout : database:database -> string -> (bool, Persistence_error.t) Result.t io
end

module Make
    (Io : Base.Monad.S)
    (Database : Database.S with type 'a io = 'a Io.t)
    (Users :
       User_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection)
    (Repository :
       Session_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection)
    (Runtime : Session_runtime.S) =
struct
  type 'a io = 'a Io.t
  type database = Database.t

  open Io.Let_syntax

  let login ~database ~username ~password =
    Database.transaction database ~on_error:Fn.id ~f:(fun ~conn ->
      let%bind authenticated = Users.authenticate ~conn ~username ~password in
      match authenticated with
      | Error error -> Io.return (Error error)
      | Ok false -> Io.return (Ok None)
      | Ok true ->
        let rec issue attempts =
          if attempts = 0 then
            Io.return (Error (`Unexpected "session token collision"))
          else (
            match
              Runtime.token ()
            with
            | Error error -> Io.return (Error (`Unexpected error))
            | Ok token when String.is_empty token ->
              Io.return (Error (`Unexpected "empty session token"))
            | Ok token ->
              let session =
                Domain.Session.{ token; username; expires_at = Runtime.now () +. 3600. }
              in
              let%bind saved = Repository.add ~conn session in
              (match saved with
               | Error error -> Io.return (Error error)
               | Ok true -> Io.return (Ok (Some session))
               | Ok false -> issue (attempts - 1)))
        in
        issue 3)
  ;;

  let find ~database token =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      let%map result = Repository.find ~conn token in
      Result.map
        result
        ~f:
          (Option.filter ~f:(fun session ->
             Float.(session.Domain.Session.expires_at > Runtime.now ()))))
  ;;

  let logout ~database token =
    Database.transaction database ~on_error:Fn.id ~f:(fun ~conn ->
      let%bind result = Repository.find ~conn token in
      match result with
      | Error error -> Io.return (Error error)
      | Ok None -> Io.return (Ok false)
      | Ok (Some session) ->
        let%map removed = Repository.remove ~conn token in
        Result.map removed ~f:(fun () -> Float.(session.expires_at > Runtime.now ())))
  ;;
end
