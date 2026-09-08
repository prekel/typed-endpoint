open! Base

module Io = struct
  type 'a t = 'a

  include Base.Monad.Make (struct
      type nonrec 'a t = 'a t

      let return value = value
      let bind value ~f = f value
      let map = `Custom (fun value ~f -> f value)
    end)
end

module Memory_pet_repository = Petstore_app.Pet_repository_memory.Make (Io)
module Pets = Petstore_app.Pet_service.Make (Io) (Memory_pet_repository)
module Memory_order_repository = Petstore_app.Order_repository_memory.Make (Io)
module Orders = Petstore_app.Order_service.Make (Io) (Memory_order_repository) (Pets)
module Memory_user_repository = Petstore_app.User_repository_memory.Make (Io)
module Users = Petstore_app.User_service.Make (Io) (Memory_user_repository)

let result_exn = function
  | Ok value -> value
  | Error _ -> Stdlib.failwith "unexpected persistence error"
;;

let order_attributes pet_id =
  Petstore_app.Domain.Order.
    { pet_id = Some pet_id
    ; quantity = Some 1
    ; ship_date = None
    ; status = Some Status.Placed
    ; complete = Some false
    }
;;

let user username password =
  Petstore_app.Domain.User.
    { username
    ; attributes =
        { id = None
        ; first_name = None
        ; last_name = None
        ; email = None
        ; password = Some password
        ; phone = None
        ; user_status = Some 1
        }
    }
;;

let place_exn orders ?id attributes =
  match Orders.place orders ?id attributes with
  | Ok order -> order
  | Error (`Already_exists id) ->
    Stdlib.failwith ("unexpected occupied order ID " ^ Int.to_string id)
  | Error (`Pet_not_found id) ->
    Stdlib.failwith ("unexpected missing pet ID " ^ Int.to_string id)
  | Error (`Persistence _) -> Stdlib.failwith "unexpected persistence error"
;;

let () =
  let open Petstore_app in
  let pets = Pets.create ~repository:(Memory_pet_repository.create ()) in
  let pet_attributes name =
    Domain.Pet.{ name; category = None; photo_urls = []; tags = None; status = None }
  in
  List.iter [ 10; 11; 12 ] ~f:(fun id ->
    assert (Result.is_ok (Pets.add pets ~id (pet_attributes "orderable"))));
  let orders = Orders.create ~repository:(Memory_order_repository.create ()) ~pets in
  let first = place_exn orders ~id:40 (order_attributes 10) in
  assert (Int.equal first.id 40);
  assert (Result.is_error (Orders.place orders ~id:40 (order_attributes 11)));
  let generated = place_exn orders (order_attributes 12) in
  assert (Int.equal generated.id 41);
  assert (Orders.find orders 41 |> result_exn |> Option.is_some);
  assert (Result.is_ok (Orders.delete orders 41));
  assert (Orders.find orders 41 |> result_exn |> Option.is_none);
  assert (
    match Orders.place orders (order_attributes 999) with
    | Error (`Pet_not_found 999) -> true
    | Ok _ | Error _ -> false);
  let users = Users.create ~repository:(Memory_user_repository.create ()) in
  assert (Result.is_ok (Users.add users (user "alice" "secret")));
  assert (Users.authenticate users ~username:"alice" ~password:"secret" |> result_exn);
  assert (not (Users.authenticate users ~username:"alice" ~password:"wrong" |> result_exn));
  let batch = [ user "bob" "one"; user "alice" "duplicate" ] in
  assert (Result.is_error (Users.add_many users batch));
  assert (Users.find users "bob" |> result_exn |> Option.is_none);
  assert (Result.is_ok (Users.add_many users [ user "bob" "one"; user "carol" "two" ]));
  assert (Result.is_ok (Users.delete users "carol"));
  assert (Result.is_error (Users.delete users "missing"))
;;
