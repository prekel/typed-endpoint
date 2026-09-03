open! Base

module Make (Io : Base.Monad.S) = struct
  type 'a io = 'a Io.t

  type t =
    { pets : (int, Domain.Pet.t) Hashtbl.t
    ; uploads : (int, (string option * string) list) Hashtbl.t
    ; mutable next_id : int
    }

  type error =
    [ `Not_found of int
    | `Persistence of Persistence_error.t
    ]

  type add_error =
    [ `Already_exists of int
    | `Persistence of Persistence_error.t
    ]

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

  let rec reserve_id repository =
    let id = repository.next_id in
    repository.next_id <- id + 1;
    if Hashtbl.mem repository.pets id then
      reserve_id repository
    else
      id
  ;;

  let advance_next_id repository id =
    if id >= repository.next_id && id < Int.max_value then
      repository.next_id <- id + 1
  ;;

  let add repository ?id attributes =
    Io.return
      (match id with
       | Some id when Hashtbl.mem repository.pets id -> Error (`Already_exists id)
       | id ->
         let id = Option.value_or_thunk id ~default:(fun () -> reserve_id repository) in
         advance_next_id repository id;
         let pet = Domain.Pet.{ id; attributes } in
         Hashtbl.set repository.pets ~key:id ~data:pet;
         Ok pet)
  ;;

  let update repository ~id attributes =
    Io.return
      (if Hashtbl.mem repository.pets id then (
         let pet = Domain.Pet.{ id; attributes } in
         Hashtbl.set repository.pets ~key:id ~data:pet;
         Ok pet)
       else
         Error (`Not_found id))
  ;;

  let patch repository ~id ?name ?status () =
    match Hashtbl.find repository.pets id with
    | None -> Io.return (Error (`Not_found id))
    | Some pet ->
      let attributes =
        { pet.Domain.Pet.attributes with
          name = Option.value name ~default:pet.attributes.name
        ; status = Option.first_some status pet.attributes.status
        }
      in
      update repository ~id attributes
  ;;

  let sorted_pets repository =
    Hashtbl.data repository.pets
    |> List.sort ~compare:(fun left right ->
      Int.compare left.Domain.Pet.id right.Domain.Pet.id)
  ;;

  let pets_by_status repository ~status =
    sorted_pets repository
    |> List.filter ~f:(fun pet ->
      Option.value_map
        pet.Domain.Pet.attributes.status
        ~default:false
        ~f:(Domain.Status.equal status))
  ;;

  let list_by_status repository ~status =
    Io.return (Ok (pets_by_status repository ~status))
  ;;

  let list_by_tags repository ~tags =
    let requested = Hash_set.of_list (module String) tags in
    sorted_pets repository
    |> List.filter ~f:(fun pet ->
      Option.value_map pet.Domain.Pet.attributes.tags ~default:false ~f:(fun tags ->
        List.exists tags ~f:(fun tag ->
          Option.value_map tag.Domain.Tag.name ~default:false ~f:(Hash_set.mem requested))))
    |> Result.return
    |> Io.return
  ;;

  let find_by_status repository ~status ~pagination =
    let matching = pets_by_status repository ~status in
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
    Io.return (Ok Domain.Page.{ items; page; limit; total; total_pages })
  ;;

  let find repository id = Io.return (Ok (Hashtbl.find repository.pets id))

  let inventory repository =
    let statuses =
      [ Domain.Status.Available; Domain.Status.Pending; Domain.Status.Sold ]
    in
    List.map statuses ~f:(fun status ->
      status, List.length (pets_by_status repository ~status))
    |> Result.return
    |> Io.return
  ;;

  let upload_image repository ~id ~metadata ~bytes =
    Io.return
      (if String.is_empty bytes then
         Error `Empty_file
       else if not (Hashtbl.mem repository.pets id) then
         Error (`Not_found id)
       else (
         Hashtbl.update repository.uploads id ~f:(function
           | None -> [ metadata, bytes ]
           | Some uploads -> (metadata, bytes) :: uploads);
         Ok (String.length bytes)))
  ;;

  let delete repository id =
    Io.return
      (if Hashtbl.mem repository.pets id then (
         Hashtbl.remove repository.pets id;
         Hashtbl.remove repository.uploads id;
         Ok ())
       else
         Error (`Not_found id))
  ;;
end
