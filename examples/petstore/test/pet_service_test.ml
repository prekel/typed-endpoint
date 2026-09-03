open! Base

let attributes name status =
  Petstore_app.Domain.Pet.
    { name; category = None; photo_urls = []; tags = None; status = Some status }
;;

let pagination ~page ~limit =
  Petstore_app.Domain.Page_request.create ~page ~limit |> Result.ok_or_failwith
;;

let add_exn service ?id attributes =
  match Petstore_app.Pet_service.add service ?id attributes with
  | Ok pet -> pet
  | Error (`Already_exists id) ->
    Stdlib.failwith ("unexpected occupied pet ID " ^ Int.to_string id)
;;

let () =
  let open Petstore_app in
  let service = Pet_service.create () in
  let explicit = add_exn service ~id:40 (attributes "Milo" Domain.Status.Available) in
  assert (Int.equal explicit.id 40);
  assert (
    match Pet_service.add service ~id:40 (attributes "Duplicate" Domain.Status.Sold) with
    | Error (`Already_exists 40) -> true
    | Ok _ | Error (`Already_exists _) -> false);
  let generated = add_exn service (attributes "Otis" Domain.Status.Available) in
  assert (Int.equal generated.id 41);
  let _ = add_exn service (attributes "Luna" Domain.Status.Sold) in
  let first =
    Pet_service.find_by_status
      service
      ~status:Domain.Status.Available
      ~pagination:(pagination ~page:1 ~limit:1)
  in
  assert (Int.equal first.total 2);
  let updated =
    match
      Pet_service.update service ~id:explicit.id (attributes "Milo" Domain.Status.Pending)
    with
    | Ok pet -> pet
    | Error (`Not_found _) -> Stdlib.failwith "existing pet was not found"
  in
  assert (
    Option.equal
      Domain.Status.equal
      updated.attributes.status
      (Some Domain.Status.Pending));
  assert (Int.equal first.total_pages 2);
  assert (List.equal Int.equal (List.map first.items ~f:(fun pet -> pet.id)) [ 40 ]);
  let beyond =
    Pet_service.find_by_status
      service
      ~status:Domain.Status.Available
      ~pagination:(pagination ~page:3 ~limit:1)
  in
  assert (List.is_empty beyond.items);
  let updated =
    match Pet_service.update service ~id:40 (attributes "Milo" Domain.Status.Sold) with
    | Ok pet -> pet
    | Error (`Not_found _) -> Stdlib.failwith "existing pet was not found"
  in
  assert (
    Domain.Status.equal (Option.value_exn updated.attributes.status) Domain.Status.Sold);
  let patched =
    match
      Pet_service.patch
        service
        ~id:40
        ~name:"Milo patched"
        ~status:Domain.Status.Pending
        ()
    with
    | Ok pet -> pet
    | Error (`Not_found _) -> Stdlib.failwith "existing pet was not found"
  in
  assert (String.equal patched.attributes.name "Milo patched");
  assert (
    Domain.Status.equal (Option.value_exn patched.attributes.status) Domain.Status.Pending);
  assert (
    Result.is_error (Pet_service.upload_image service ~id:40 ~metadata:None ~bytes:""));
  assert (
    Result.equal
      Int.equal
      Poly.equal
      (Pet_service.upload_image service ~id:40 ~metadata:(Some "profile") ~bytes:"data")
      (Ok 4));
  let inventory = Pet_service.inventory service in
  let count status = List.Assoc.find_exn inventory ~equal:Domain.Status.equal status in
  assert (Int.equal (count Domain.Status.Pending) 1);
  assert (Result.is_error (Pet_service.update service ~id:999 updated.attributes));
  assert (Result.is_ok (Pet_service.delete service 40));
  assert (Option.is_none (Pet_service.find service 40));
  assert (Result.is_error (Domain.Page_request.create ~page:0 ~limit:20));
  assert (Result.is_error (Domain.Page_request.create ~page:1 ~limit:101))
;;
