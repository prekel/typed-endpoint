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

let result_exn = function
  | Ok value -> value
  | Error _ -> Stdlib.failwith "unexpected persistence error"
;;

let attributes name status =
  Petstore_app.Domain.Pet.
    { name; category = None; photo_urls = []; tags = None; status = Some status }
;;

let pagination ~page ~limit =
  Petstore_app.Domain.Page_request.create ~page ~limit |> Result.ok_or_failwith
;;

let add_exn database ?id attributes =
  match Pets.add ~database ?id attributes with
  | Ok pet -> pet
  | Error (`Already_exists id) ->
    Stdlib.failwith ("unexpected occupied pet ID " ^ Int.to_string id)
  | Error (`Persistence _) -> Stdlib.failwith "unexpected persistence error"
;;

let () =
  let open Petstore_app in
  let database = Memory_database.create () in
  let explicit = add_exn database ~id:40 (attributes "Milo" Domain.Status.Available) in
  assert (Int.equal explicit.id 40);
  assert (
    match Pets.add ~database ~id:40 (attributes "Duplicate" Domain.Status.Sold) with
    | Error (`Already_exists 40) -> true
    | Ok _ | Error (`Already_exists _) | Error (`Persistence _) -> false);
  let generated = add_exn database (attributes "Otis" Domain.Status.Available) in
  assert (Int.equal generated.id 41);
  let _ = add_exn database (attributes "Luna" Domain.Status.Sold) in
  let first =
    Pets.find_by_status
      ~database
      ~status:Domain.Status.Available
      ~pagination:(pagination ~page:1 ~limit:1)
    |> result_exn
  in
  assert (Int.equal first.total 2);
  let updated =
    match
      Pets.update ~database ~id:explicit.id (attributes "Milo" Domain.Status.Pending)
    with
    | Ok pet -> pet
    | Error (`Not_found _) -> Stdlib.failwith "existing pet was not found"
    | Error (`Persistence _) -> Stdlib.failwith "unexpected persistence error"
  in
  assert (
    Option.equal
      Domain.Status.equal
      updated.attributes.status
      (Some Domain.Status.Pending));
  assert (Int.equal first.total_pages 2);
  assert (List.equal Int.equal (List.map first.items ~f:(fun pet -> pet.id)) [ 40 ]);
  let beyond =
    Pets.find_by_status
      ~database
      ~status:Domain.Status.Available
      ~pagination:(pagination ~page:3 ~limit:1)
    |> result_exn
  in
  assert (List.is_empty beyond.items);
  let updated =
    match Pets.update ~database ~id:40 (attributes "Milo" Domain.Status.Sold) with
    | Ok pet -> pet
    | Error (`Not_found _) -> Stdlib.failwith "existing pet was not found"
    | Error (`Persistence _) -> Stdlib.failwith "unexpected persistence error"
  in
  assert (
    Domain.Status.equal (Option.value_exn updated.attributes.status) Domain.Status.Sold);
  let patched =
    match
      Pets.patch ~database ~id:40 ~name:"Milo patched" ~status:Domain.Status.Pending ()
    with
    | Ok pet -> pet
    | Error (`Not_found _) -> Stdlib.failwith "existing pet was not found"
    | Error (`Persistence _) -> Stdlib.failwith "unexpected persistence error"
  in
  assert (String.equal patched.attributes.name "Milo patched");
  assert (
    Domain.Status.equal (Option.value_exn patched.attributes.status) Domain.Status.Pending);
  assert (Result.is_error (Pets.upload_image ~database ~id:40 ~metadata:None ~bytes:""));
  assert (
    Result.equal
      Int.equal
      Poly.equal
      (Pets.upload_image ~database ~id:40 ~metadata:(Some "profile") ~bytes:"data")
      (Ok 4));
  let inventory = Pets.inventory ~database |> result_exn in
  let count status = List.Assoc.find_exn inventory ~equal:Domain.Status.equal status in
  assert (Int.equal (count Domain.Status.Pending) 1);
  assert (Result.is_error (Pets.update ~database ~id:999 updated.attributes));
  assert (Result.is_ok (Pets.delete ~database 40));
  assert (Pets.find ~database 40 |> result_exn |> Option.is_none);
  assert (Result.is_error (Domain.Page_request.create ~page:0 ~limit:20));
  assert (Result.is_error (Domain.Page_request.create ~page:1 ~limit:101))
;;
