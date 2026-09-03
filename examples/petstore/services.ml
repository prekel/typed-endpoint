open! Base

type t =
  { pets : Pet_service.t
  ; orders : Order_service.t
  ; users : User_service.t
  }

let create () =
  { pets = Pet_service.create ()
  ; orders = Order_service.create ()
  ; users = User_service.create ()
  }
;;

let pets t = t.pets
let orders t = t.orders
let users t = t.users
