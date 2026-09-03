open! Base

module type S = sig
  type 'a io
  type t

  val place
    :  t
    -> ?id:int
    -> Domain.Order.attributes
    -> ( Domain.Order.t
         , [ `Already_exists of int
           | `Pet_not_found of int
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         io

  val find : t -> int -> (Domain.Order.t option, Persistence_error.t) Result.t io

  val delete
    :  t
    -> int
    -> (unit, [ `Not_found of int | `Persistence of Persistence_error.t ]) Result.t io
end

module Make
    (Io : Base.Monad.S)
    (Repository : Order_repository.S with type 'a io = 'a Io.t)
    (Pets : Pet_service.S with type 'a io = 'a Io.t) =
struct
  type 'a io = 'a Io.t

  type t =
    { repository : Repository.t
    ; pets : Pets.t
    }

  let create ~repository ~pets = { repository; pets }

  let place_in_repository t ?id attributes =
    let open Io.Let_syntax in
    let%map result = Repository.place t.repository ?id attributes in
    match result with
    | Ok order -> Ok order
    | Error (`Already_exists id) -> Error (`Already_exists id)
    | Error (`Persistence error) -> Error (`Persistence error)
  ;;

  let place t ?id attributes =
    let open Io.Let_syntax in
    match attributes.Domain.Order.pet_id with
    | None -> place_in_repository t ?id attributes
    | Some pet_id ->
      let%bind pet = Pets.find t.pets pet_id in
      (match pet with
       | Error error -> Io.return (Error (`Persistence error))
       | Ok None -> Io.return (Error (`Pet_not_found pet_id))
       | Ok (Some _) -> place_in_repository t ?id attributes)
  ;;

  let find t = Repository.find t.repository
  let delete t = Repository.delete t.repository
end
