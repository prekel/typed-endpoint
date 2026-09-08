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

module Database = Petstore_app.Database_memory.Make (Io)
module Pets = Database.Pet_repository

let attributes name =
  Petstore_app.Domain.Pet.
    { name; category = None; photo_urls = []; tags = None; status = None }
;;

let add_in_transaction database ~id ~name =
  Database.transaction
    database
    ~on_error:(fun error -> `Persistence error)
    ~f:(fun ~conn -> Pets.add ~conn ~id (attributes name))
;;

let find database id =
  match
    Database.with_connection database ~on_error:Fn.id ~f:(fun ~conn -> Pets.find ~conn id)
  with
  | Ok pet -> pet
  | Error _ -> Stdlib.failwith "unexpected persistence error"
;;

let test_commit () =
  let database = Database.create () in
  assert (Result.is_ok (add_in_transaction database ~id:1 ~name:"committed"));
  assert (find database 1 |> Option.is_some)
;;

let test_error_rolls_back () =
  let database = Database.create () in
  let result =
    Database.transaction
      database
      ~on_error:(fun error -> `Persistence error)
      ~f:(fun ~conn ->
        ignore (Pets.add ~conn ~id:1 (attributes "rolled back"));
        Error `Abort)
  in
  assert (Result.equal Unit.equal Poly.equal result (Error `Abort));
  assert (find database 1 |> Option.is_none)
;;

let test_exception_rolls_back () =
  let database = Database.create () in
  let raised =
    try
      ignore
        (Database.transaction
           database
           ~on_error:(fun error -> `Persistence error)
           ~f:(fun ~conn ->
             ignore (Pets.add ~conn ~id:1 (attributes "raised"));
             Stdlib.failwith "transaction callback failed"));
      false
    with
    | Failure message -> String.equal message "transaction callback failed"
    | _ -> false
  in
  assert raised;
  assert (find database 1 |> Option.is_none)
;;

let test_optimistic_conflict () =
  let database = Database.create () in
  let result =
    Database.transaction database ~on_error:Fn.id ~f:(fun ~conn ->
      assert (Result.is_ok (add_in_transaction database ~id:2 ~name:"inner"));
      ignore (Pets.add ~conn ~id:1 (attributes "outer"));
      Ok ())
  in
  assert (
    match result with
    | Error (`Unexpected "concurrent in-memory transaction conflict") -> true
    | Ok () | Error _ -> false);
  assert (find database 1 |> Option.is_none);
  assert (find database 2 |> Option.is_some)
;;

let () =
  test_commit ();
  test_error_rolls_back ();
  test_exception_rolls_back ();
  test_optimistic_conflict ()
;;
