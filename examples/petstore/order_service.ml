open! Base

type t =
  { orders : (int, Domain.Order.t) Hashtbl.t
  ; mutable next_id : int
  }

type error = [ `Not_found of int ]
type place_error = [ `Already_exists of int ]

let create () = { orders = Hashtbl.create (module Int); next_id = 1 }

let rec reserve_id service =
  let id = service.next_id in
  service.next_id <- id + 1;
  if Hashtbl.mem service.orders id then
    reserve_id service
  else
    id
;;

let advance_next_id service id =
  if id >= service.next_id && id < Int.max_value then
    service.next_id <- id + 1
;;

let place service ?id attributes =
  match id with
  | Some id when Hashtbl.mem service.orders id -> Error (`Already_exists id)
  | id ->
    let id = Option.value_or_thunk id ~default:(fun () -> reserve_id service) in
    advance_next_id service id;
    let order = Domain.Order.{ id; attributes } in
    Hashtbl.set service.orders ~key:id ~data:order;
    Ok order
;;

let find service id = Hashtbl.find service.orders id

let delete service id =
  if Hashtbl.mem service.orders id then (
    Hashtbl.remove service.orders id;
    Ok ())
  else
    Error (`Not_found id)
;;
