open! Base

type t =
  { pets : (int, Dto.Pet.t) Hashtbl.t
  ; mutable next_id : int
  }

let create () = { pets = Hashtbl.create (module Int); next_id = 1 }

let reserve_id service =
  let id = service.next_id in
  service.next_id <- id + 1;
  id
;;

let add service pet =
  let id = Option.value pet.Dto.Pet.id ~default:(reserve_id service) in
  let pet = { pet with id = Some id } in
  Hashtbl.set service.pets ~key:id ~data:pet;
  pet
;;

let update service pet =
  match pet.Dto.Pet.id with
  | None ->
    Error
      Dto.Api_response.{ code = 400; type_ = "invalid_pet"; message = "id is required" }
  | Some id when Hashtbl.mem service.pets id ->
    Hashtbl.set service.pets ~key:id ~data:pet;
    Ok pet
  | Some id -> Error (Dto.Api_response.not_found id)
;;

let find_by_status service status =
  Hashtbl.data service.pets
  |> List.filter ~f:(fun pet ->
    Option.value_map pet.Dto.Pet.status ~default:false ~f:(String.equal status))
  |> List.sort ~compare:(fun left right ->
    Option.compare Int.compare left.Dto.Pet.id right.Dto.Pet.id)
;;

let find service id = Hashtbl.find service.pets id

let delete service id =
  if Hashtbl.mem service.pets id then (
    Hashtbl.remove service.pets id;
    Ok ())
  else
    Error (Dto.Api_response.not_found id)
;;
