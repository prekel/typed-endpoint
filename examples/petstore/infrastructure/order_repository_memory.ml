open! Base

module Make (Io : Base.Monad.S) = struct
  type 'a io = 'a Io.t

  type t =
    { orders : (int, Domain.Order.t) Hashtbl.t
    ; mutable next_id : int
    }

  type error =
    [ `Not_found of int
    | `Persistence of Persistence_error.t
    ]

  type place_error =
    [ `Already_exists of int
    | `Persistence of Persistence_error.t
    ]

  let create () = { orders = Hashtbl.create (module Int); next_id = 1 }

  let rec reserve_id repository =
    let id = repository.next_id in
    repository.next_id <- id + 1;
    if Hashtbl.mem repository.orders id then
      reserve_id repository
    else
      id
  ;;

  let advance_next_id repository id =
    if id >= repository.next_id && id < Int.max_value then
      repository.next_id <- id + 1
  ;;

  let place repository ?id attributes =
    Io.return
      (match id with
       | Some id when Hashtbl.mem repository.orders id -> Error (`Already_exists id)
       | id ->
         let id = Option.value_or_thunk id ~default:(fun () -> reserve_id repository) in
         advance_next_id repository id;
         let order = Domain.Order.{ id; attributes } in
         Hashtbl.set repository.orders ~key:id ~data:order;
         Ok order)
  ;;

  let find repository id = Io.return (Ok (Hashtbl.find repository.orders id))

  let delete repository id =
    Io.return
      (if Hashtbl.mem repository.orders id then (
         Hashtbl.remove repository.orders id;
         Ok ())
       else
         Error (`Not_found id))
  ;;
end
