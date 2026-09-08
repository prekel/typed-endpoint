open! Base

module Make (Io : Base.Monad.S) = struct
  type 'a io = 'a Io.t

  type state =
    { pets : (int, Domain.Pet.t) Hashtbl.t
    ; uploads : (int, (string option * string) list) Hashtbl.t
    ; mutable next_pet_id : int
    ; orders : (int, Domain.Order.t) Hashtbl.t
    ; mutable next_order_id : int
    ; users : (string, Domain.User.t) Hashtbl.t
    }

  type connection = state

  type t =
    { mutable version : int
    ; mutable state : state
    }

  let empty_state () =
    { pets = Hashtbl.create (module Int)
    ; uploads = Hashtbl.create (module Int)
    ; next_pet_id = 1
    ; orders = Hashtbl.create (module Int)
    ; next_order_id = 1
    ; users = Hashtbl.create (module String)
    }
  ;;

  let create () = { version = 0; state = empty_state () }

  let copy_state state =
    { pets = Hashtbl.copy state.pets
    ; uploads = Hashtbl.copy state.uploads
    ; next_pet_id = state.next_pet_id
    ; orders = Hashtbl.copy state.orders
    ; next_order_id = state.next_order_id
    ; users = Hashtbl.copy state.users
    }
  ;;

  let with_connection database ~on_error:_ ~f = f ~conn:database.state

  let transaction database ~on_error ~f =
    let expected_version = database.version in
    let conn = copy_state database.state in
    let open Io.Let_syntax in
    let%map result = f ~conn in
    match result with
    | Error _ -> result
    | Ok _ when not (Int.equal database.version expected_version) ->
      Error (on_error (`Unexpected "concurrent in-memory transaction conflict"))
    | Ok _ ->
      database.state <- conn;
      database.version <- expected_version + 1;
      result
  ;;

  module Pet_repository = struct
    type nonrec 'a io = 'a io
    type nonrec connection = connection

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

    let rec reserve_id conn =
      let id = conn.next_pet_id in
      conn.next_pet_id <- id + 1;
      if Hashtbl.mem conn.pets id then
        reserve_id conn
      else
        id
    ;;

    let advance_next_id conn id =
      if id >= conn.next_pet_id && id < Int.max_value then
        conn.next_pet_id <- id + 1
    ;;

    let add ~conn ?id attributes =
      Io.return
        (match id with
         | Some id when Hashtbl.mem conn.pets id -> Error (`Already_exists id)
         | id ->
           let id = Option.value_or_thunk id ~default:(fun () -> reserve_id conn) in
           advance_next_id conn id;
           let pet = Domain.Pet.{ id; attributes } in
           Hashtbl.set conn.pets ~key:id ~data:pet;
           Ok pet)
    ;;

    let update ~conn ~id attributes =
      Io.return
        (if Hashtbl.mem conn.pets id then (
           let pet = Domain.Pet.{ id; attributes } in
           Hashtbl.set conn.pets ~key:id ~data:pet;
           Ok pet)
         else
           Error (`Not_found id))
    ;;

    let patch ~conn ~id ?name ?status () =
      match Hashtbl.find conn.pets id with
      | None -> Io.return (Error (`Not_found id))
      | Some pet ->
        let attributes =
          { pet.Domain.Pet.attributes with
            name = Option.value name ~default:pet.attributes.name
          ; status = Option.first_some status pet.attributes.status
          }
        in
        update ~conn ~id attributes
    ;;

    let sorted_pets conn =
      Hashtbl.data conn.pets
      |> List.sort ~compare:(fun left right ->
        Int.compare left.Domain.Pet.id right.Domain.Pet.id)
    ;;

    let pets_by_status conn ~status =
      sorted_pets conn
      |> List.filter ~f:(fun pet ->
        Option.value_map
          pet.Domain.Pet.attributes.status
          ~default:false
          ~f:(Domain.Status.equal status))
    ;;

    let list_by_status ~conn ~status = Io.return (Ok (pets_by_status conn ~status))

    let list_by_tags ~conn ~tags =
      let requested = Hash_set.of_list (module String) tags in
      sorted_pets conn
      |> List.filter ~f:(fun pet ->
        Option.value_map pet.Domain.Pet.attributes.tags ~default:false ~f:(fun tags ->
          List.exists tags ~f:(fun tag ->
            Option.value_map
              tag.Domain.Tag.name
              ~default:false
              ~f:(Hash_set.mem requested))))
      |> Result.return
      |> Io.return
    ;;

    let find_by_status ~conn ~status ~pagination =
      let matching = pets_by_status conn ~status in
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

    let find ~conn id = Io.return (Ok (Hashtbl.find conn.pets id))

    let inventory ~conn =
      let statuses =
        [ Domain.Status.Available; Domain.Status.Pending; Domain.Status.Sold ]
      in
      List.map statuses ~f:(fun status ->
        status, List.length (pets_by_status conn ~status))
      |> Result.return
      |> Io.return
    ;;

    let upload_image ~conn ~id ~metadata ~bytes =
      Io.return
        (if String.is_empty bytes then
           Error `Empty_file
         else if not (Hashtbl.mem conn.pets id) then
           Error (`Not_found id)
         else (
           Hashtbl.update conn.uploads id ~f:(function
             | None -> [ metadata, bytes ]
             | Some uploads -> (metadata, bytes) :: uploads);
           Ok (String.length bytes)))
    ;;

    let delete ~conn id =
      Io.return
        (if Hashtbl.mem conn.pets id then (
           Hashtbl.remove conn.pets id;
           Hashtbl.remove conn.uploads id;
           Ok ())
         else
           Error (`Not_found id))
    ;;
  end

  module Order_repository = struct
    type nonrec 'a io = 'a io
    type nonrec connection = connection

    type error =
      [ `Not_found of int
      | `Persistence of Persistence_error.t
      ]

    type place_error =
      [ `Already_exists of int
      | `Persistence of Persistence_error.t
      ]

    let rec reserve_id conn =
      let id = conn.next_order_id in
      conn.next_order_id <- id + 1;
      if Hashtbl.mem conn.orders id then
        reserve_id conn
      else
        id
    ;;

    let advance_next_id conn id =
      if id >= conn.next_order_id && id < Int.max_value then
        conn.next_order_id <- id + 1
    ;;

    let place ~conn ?id attributes =
      Io.return
        (match id with
         | Some id when Hashtbl.mem conn.orders id -> Error (`Already_exists id)
         | id ->
           let id = Option.value_or_thunk id ~default:(fun () -> reserve_id conn) in
           advance_next_id conn id;
           let order = Domain.Order.{ id; attributes } in
           Hashtbl.set conn.orders ~key:id ~data:order;
           Ok order)
    ;;

    let find ~conn id = Io.return (Ok (Hashtbl.find conn.orders id))

    let delete ~conn id =
      Io.return
        (if Hashtbl.mem conn.orders id then (
           Hashtbl.remove conn.orders id;
           Ok ())
         else
           Error (`Not_found id))
    ;;
  end

  module User_repository = struct
    type nonrec 'a io = 'a io
    type nonrec connection = connection

    type error =
      [ `Not_found of string
      | `Persistence of Persistence_error.t
      ]

    type create_error =
      [ `Already_exists of string
      | `Persistence of Persistence_error.t
      ]

    let add ~conn user =
      Io.return
        (if Hashtbl.mem conn.users user.Domain.User.username then
           Error (`Already_exists user.username)
         else (
           Hashtbl.set conn.users ~key:user.username ~data:user;
           Ok user))
    ;;

    let duplicate_username conn users =
      let seen = Hash_set.create (module String) in
      List.find_map users ~f:(fun user ->
        let username = user.Domain.User.username in
        if Hashtbl.mem conn.users username || Hash_set.mem seen username then
          Some username
        else (
          Hash_set.add seen username;
          None))
    ;;

    let add_many ~conn users =
      Io.return
        (match duplicate_username conn users with
         | Some username -> Error (`Already_exists username)
         | None ->
           List.iter users ~f:(fun user ->
             Hashtbl.set conn.users ~key:user.Domain.User.username ~data:user);
           Ok users)
    ;;

    let find ~conn username = Io.return (Ok (Hashtbl.find conn.users username))

    let update ~conn ~username user =
      Io.return
        (if Hashtbl.mem conn.users username then (
           let user = { user with Domain.User.username } in
           Hashtbl.set conn.users ~key:username ~data:user;
           Ok user)
         else
           Error (`Not_found username))
    ;;

    let delete ~conn username =
      Io.return
        (if Hashtbl.mem conn.users username then (
           Hashtbl.remove conn.users username;
           Ok ())
         else
           Error (`Not_found username))
    ;;

    let authenticate ~conn ~username ~password =
      Hashtbl.find conn.users username
      |> Option.value_map ~default:false ~f:(fun user ->
        Option.value_map
          user.Domain.User.attributes.password
          ~default:false
          ~f:(String.equal password))
      |> Result.return
      |> Io.return
    ;;
  end
end
