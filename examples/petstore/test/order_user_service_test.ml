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

module Memory = Petstore_app.Memory_services.Make (Io)

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
  match Memory.Orders.place orders ?id attributes with
  | Ok order -> order
  | Error (`Already_exists id) ->
    Stdlib.failwith ("unexpected occupied order ID " ^ Int.to_string id)
  | Error (`Pet_not_found id) ->
    Stdlib.failwith ("unexpected missing pet ID " ^ Int.to_string id)
  | Error (`Persistence _) -> Stdlib.failwith "unexpected persistence error"
;;

let () =
  let open Petstore_app in
  let services = Memory.create () in
  let pets = Services.pets services in
  let pet_attributes name =
    Domain.Pet.{ name; category = None; photo_urls = []; tags = None; status = None }
  in
  List.iter [ 10; 11; 12 ] ~f:(fun id ->
    assert (Result.is_ok (Memory.Pets.add pets ~id (pet_attributes "orderable"))));
  let orders = Services.orders services in
  let first = place_exn orders ~id:40 (order_attributes 10) in
  assert (Int.equal first.id 40);
  assert (Result.is_error (Memory.Orders.place orders ~id:40 (order_attributes 11)));
  let generated = place_exn orders (order_attributes 12) in
  assert (Int.equal generated.id 41);
  assert (Memory.Orders.find orders 41 |> result_exn |> Option.is_some);
  assert (Result.is_ok (Memory.Orders.delete orders 41));
  assert (Memory.Orders.find orders 41 |> result_exn |> Option.is_none);
  assert (
    match Memory.Orders.place orders (order_attributes 999) with
    | Error (`Pet_not_found 999) -> true
    | Ok _ | Error _ -> false);
  let users = Services.users services in
  assert (Result.is_ok (Memory.Users.add users (user "alice" "secret")));
  assert (
    Memory.Users.authenticate users ~username:"alice" ~password:"secret" |> result_exn);
  assert (
    not (Memory.Users.authenticate users ~username:"alice" ~password:"wrong" |> result_exn));
  let batch = [ user "bob" "one"; user "alice" "duplicate" ] in
  assert (Result.is_error (Memory.Users.add_many users batch));
  assert (Memory.Users.find users "bob" |> result_exn |> Option.is_none);
  assert (
    Result.is_ok (Memory.Users.add_many users [ user "bob" "one"; user "carol" "two" ]));
  assert (Result.is_ok (Memory.Users.delete users "carol"));
  assert (Result.is_error (Memory.Users.delete users "missing"))
;;
