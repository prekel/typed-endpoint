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

module Memory_database = Petstore_app.Database_memory.Make (Io)

module Pets =
  Petstore_app.Pet_service.Make (Io) (Memory_database) (Memory_database.Pet_repository)

let last_pet_connection : Memory_database.connection option ref = ref None
let order_used_pet_connection = ref false

module Tracking_pet_repository = struct
  include Memory_database.Pet_repository

  let find ~conn id =
    last_pet_connection := Some conn;
    find ~conn id
  ;;
end

module Tracking_order_repository = struct
  include Memory_database.Order_repository

  let place ~conn ?id attributes =
    order_used_pet_connection
    := Option.value_map !last_pet_connection ~default:false ~f:(phys_equal conn);
    place ~conn ?id attributes
  ;;
end

module Orders =
  Petstore_app.Order_service.Make (Io) (Memory_database) (Tracking_pet_repository)
    (Tracking_order_repository)

module Users =
  Petstore_app.User_service.Make (Io) (Memory_database) (Memory_database.User_repository)
    (Memory_database.Session_repository)

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

let place_exn database ?id attributes =
  match Orders.place ~database ?id attributes with
  | Ok order -> order
  | Error (`Already_exists id) ->
    Stdlib.failwith ("unexpected occupied order ID " ^ Int.to_string id)
  | Error (`Pet_not_found id) ->
    Stdlib.failwith ("unexpected missing pet ID " ^ Int.to_string id)
  | Error (`Persistence _) -> Stdlib.failwith "unexpected persistence error"
;;

let () =
  let open Petstore_app in
  let database = Memory_database.create () in
  let pet_attributes name =
    Domain.Pet.{ name; category = None; photo_urls = []; tags = None; status = None }
  in
  List.iter [ 10; 11; 12 ] ~f:(fun id ->
    assert (Result.is_ok (Pets.add ~database ~id (pet_attributes "orderable"))));
  let first = place_exn database ~id:40 (order_attributes 10) in
  assert (Int.equal first.id 40);
  assert !order_used_pet_connection;
  assert (Result.is_error (Orders.place ~database ~id:40 (order_attributes 11)));
  let generated = place_exn database (order_attributes 12) in
  assert (Int.equal generated.id 41);
  assert (Orders.find ~database 41 |> result_exn |> Option.is_some);
  assert (Result.is_ok (Orders.delete ~database 41));
  assert (Orders.find ~database 41 |> result_exn |> Option.is_none);
  assert (
    match Orders.place ~database (order_attributes 999) with
    | Error (`Pet_not_found 999) -> true
    | Ok _ | Error _ -> false);
  assert (Result.is_ok (Users.add ~database (user "alice" "secret")));
  assert (Users.authenticate ~database ~username:"alice" ~password:"secret" |> result_exn);
  assert (
    not (Users.authenticate ~database ~username:"alice" ~password:"wrong" |> result_exn));
  let batch = [ user "bob" "one"; user "alice" "duplicate" ] in
  assert (
    Result.is_error
      (Users.add_many ~database ~actor:Petstore_app.Domain.User.Administrator batch));
  assert (Users.find ~database "bob" |> result_exn |> Option.is_none);
  assert (
    Result.is_ok
      (Users.add_many
         ~database
         ~actor:Petstore_app.Domain.User.Administrator
         [ user "bob" "one"; user "carol" "two" ]));
  assert (
    Result.is_ok
      (Users.delete ~database ~actor:Petstore_app.Domain.User.Administrator "carol"));
  assert (
    Result.is_error
      (Users.delete ~database ~actor:Petstore_app.Domain.User.Administrator "missing"))
;;

module Failing_sessions = struct
  include Memory_database.Session_repository

  let remove_by_username ~conn ~username =
    let _ = remove_by_username ~conn ~username in
    Error `Unavailable
  ;;
end

module Failing_users =
  Petstore_app.User_service.Make (Io) (Memory_database) (Memory_database.User_repository)
    (Failing_sessions)

let () =
  let database = Memory_database.create () in
  let actor = Petstore_app.Domain.User.Administrator in
  assert (Result.is_ok (Users.add ~database (user "atomic" "original")));
  let saved =
    Memory_database.transaction database ~on_error:Fn.id ~f:(fun ~conn ->
      Memory_database.Session_repository.add
        ~conn
        Petstore_app.Domain.Session.
          { token = "old-session"; username = "atomic"; expires_at = 100. })
  in
  assert (Poly.equal saved (Ok true));
  let session_exists () =
    Memory_database.with_connection database ~on_error:Fn.id ~f:(fun ~conn ->
      Memory_database.Session_repository.find ~conn "old-session")
    |> result_exn
    |> Option.is_some
  in
  assert (
    Result.is_error
      (Failing_users.update
         ~database
         ~actor
         ~username:"atomic"
         (user "atomic" "replacement")));
  assert (
    Users.authenticate ~database ~username:"atomic" ~password:"original" |> result_exn);
  assert (
    not
      (Users.authenticate ~database ~username:"atomic" ~password:"replacement"
       |> result_exn));
  assert (session_exists ());
  assert (Result.is_error (Failing_users.delete ~database ~actor "atomic"));
  assert (Users.find ~database "atomic" |> result_exn |> Option.is_some);
  assert (session_exists ());
  let other = Petstore_app.Domain.User.Session_user "other" in
  assert (Poly.equal (Users.delete ~database ~actor:other "atomic") (Error `Forbidden));
  assert (
    Poly.equal
      (Users.add_many ~database ~actor:other [ user "denied" "secret" ])
      (Error `Forbidden));
  assert (Users.find ~database "denied" |> result_exn |> Option.is_none)
;;
