open! Base

module type S = sig
  type 'a io
  type database

  val place
    :  database:database
    -> ?id:int
    -> Domain.Order.attributes
    -> ( Domain.Order.t
         , [ `Already_exists of int
           | `Pet_not_found of int
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         io

  val find
    :  database:database
    -> int
    -> (Domain.Order.t option, Persistence_error.t) Result.t io

  val delete
    :  database:database
    -> int
    -> (unit, [ `Not_found of int | `Persistence of Persistence_error.t ]) Result.t io
end

module Make
    (Io : Base.Monad.S)
    (Database : Database.S with type 'a io = 'a Io.t)
    (Pets :
       Pet_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection)
    (Orders :
       Order_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection) =
struct
  type 'a io = 'a Io.t
  type database = Database.t

  let place_in_repository ~conn ?id attributes =
    let open Io.Let_syntax in
    let%map result = Orders.place ~conn ?id attributes in
    match result with
    | Ok order -> Ok order
    | Error (`Already_exists id) -> Error (`Already_exists id)
    | Error (`Persistence error) -> Error (`Persistence error)
  ;;

  let place ~database ?id attributes =
    Database.transaction
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn ->
        let open Io.Let_syntax in
        match attributes.Domain.Order.pet_id with
        | None -> place_in_repository ~conn ?id attributes
        | Some pet_id ->
          let%bind pet = Pets.find ~conn pet_id in
          (match pet with
           | Error error -> Io.return (Error (`Persistence error))
           | Ok None -> Io.return (Error (`Pet_not_found pet_id))
           | Ok (Some _) -> place_in_repository ~conn ?id attributes))
  ;;

  let find ~database id =
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Orders.find ~conn id)
  ;;

  let delete ~database id =
    Database.transaction
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn -> Orders.delete ~conn id)
  ;;
end
