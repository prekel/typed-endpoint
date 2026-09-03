open! Base

type t =
  { pets : (int, Domain.Pet.t) Hashtbl.t
  ; uploads : (int, (string option * string) list) Hashtbl.t
  ; mutable next_id : int
  }

type error = [ `Not_found of int ]
type add_error = [ `Already_exists of int ]

type upload_error =
  [ error
  | `Empty_file
  ]

let create () =
  { pets = Hashtbl.create (module Int)
  ; uploads = Hashtbl.create (module Int)
  ; next_id = 1
  }
;;

let rec reserve_id service =
  let id = service.next_id in
  service.next_id <- id + 1;
  if Hashtbl.mem service.pets id then
    reserve_id service
  else
    id
;;

let advance_next_id service id =
  if id >= service.next_id && id < Int.max_value then
    service.next_id <- id + 1
;;

let add service ?id attributes =
  match id with
  | Some id when Hashtbl.mem service.pets id -> Error (`Already_exists id)
  | id ->
    let id = Option.value_or_thunk id ~default:(fun () -> reserve_id service) in
    advance_next_id service id;
    let pet = Domain.Pet.{ id; attributes } in
    Hashtbl.set service.pets ~key:id ~data:pet;
    Ok pet
;;

let update service ~id attributes =
  if Hashtbl.mem service.pets id then (
    let pet = Domain.Pet.{ id; attributes } in
    Hashtbl.set service.pets ~key:id ~data:pet;
    Ok pet)
  else
    Error (`Not_found id)
;;

let patch service ~id ?name ?status () =
  match Hashtbl.find service.pets id with
  | None -> Error (`Not_found id)
  | Some pet ->
    let attributes =
      { pet.Domain.Pet.attributes with
        name = Option.value name ~default:pet.attributes.name
      ; status = Option.first_some status pet.attributes.status
      }
    in
    update service ~id attributes
;;

let sorted_pets service =
  Hashtbl.data service.pets
  |> List.sort ~compare:(fun left right ->
    Int.compare left.Domain.Pet.id right.Domain.Pet.id)
;;

let list_by_status service ~status =
  sorted_pets service
  |> List.filter ~f:(fun pet ->
    Option.value_map
      pet.Domain.Pet.attributes.status
      ~default:false
      ~f:(Domain.Status.equal status))
;;

let list_by_tags service ~tags =
  let requested = Hash_set.of_list (module String) tags in
  sorted_pets service
  |> List.filter ~f:(fun pet ->
    Option.value_map pet.Domain.Pet.attributes.tags ~default:false ~f:(fun tags ->
      List.exists tags ~f:(fun tag ->
        Option.value_map tag.Domain.Tag.name ~default:false ~f:(Hash_set.mem requested))))
;;

let find_by_status service ~status ~pagination =
  let matching = list_by_status service ~status in
  let page = Domain.Page_request.page pagination in
  let limit = Domain.Page_request.limit pagination in
  let total = List.length matching in
  let total_pages =
    if Int.equal total 0 then
      0
    else
      (total + limit - 1) / limit
  in
  let offset = (page - 1) * limit in
  let items =
    matching |> fun pets ->
    List.drop pets offset |> fun pets -> List.take pets limit
  in
  Domain.Page.{ items; page; limit; total; total_pages }
;;

let find service id = Hashtbl.find service.pets id

let inventory service =
  let statuses = [ Domain.Status.Available; Domain.Status.Pending; Domain.Status.Sold ] in
  List.map statuses ~f:(fun status ->
    status, List.length (list_by_status service ~status))
;;

let upload_image service ~id ~metadata ~bytes =
  if String.is_empty bytes then
    Error `Empty_file
  else if not (Hashtbl.mem service.pets id) then
    Error (`Not_found id)
  else (
    Hashtbl.update service.uploads id ~f:(function
      | None -> [ metadata, bytes ]
      | Some uploads -> (metadata, bytes) :: uploads);
    Ok (String.length bytes))
;;

let delete service id =
  if Hashtbl.mem service.pets id then (
    Hashtbl.remove service.pets id;
    Hashtbl.remove service.uploads id;
    Ok ())
  else
    Error (`Not_found id)
;;
