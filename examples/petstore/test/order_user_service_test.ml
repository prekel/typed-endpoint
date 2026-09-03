open! Base

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
  match Petstore_app.Order_service.place orders ?id attributes with
  | Ok order -> order
  | Error (`Already_exists id) ->
    Stdlib.failwith ("unexpected occupied order ID " ^ Int.to_string id)
;;

let () =
  let open Petstore_app in
  let orders = Order_service.create () in
  let first = place_exn orders ~id:40 (order_attributes 10) in
  assert (Int.equal first.id 40);
  assert (Result.is_error (Order_service.place orders ~id:40 (order_attributes 11)));
  let generated = place_exn orders (order_attributes 12) in
  assert (Int.equal generated.id 41);
  assert (Option.is_some (Order_service.find orders 41));
  assert (Result.is_ok (Order_service.delete orders 41));
  assert (Option.is_none (Order_service.find orders 41));
  let users = User_service.create () in
  assert (Result.is_ok (User_service.add users (user "alice" "secret")));
  assert (User_service.authenticate users ~username:"alice" ~password:"secret");
  assert (not (User_service.authenticate users ~username:"alice" ~password:"wrong"));
  let batch = [ user "bob" "one"; user "alice" "duplicate" ] in
  assert (Result.is_error (User_service.add_many users batch));
  assert (Option.is_none (User_service.find users "bob"));
  assert (
    Result.is_ok (User_service.add_many users [ user "bob" "one"; user "carol" "two" ]));
  assert (Result.is_ok (User_service.delete users "carol"));
  assert (Result.is_error (User_service.delete users "missing"))
;;
