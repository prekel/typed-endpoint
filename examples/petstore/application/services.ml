open! Base

type ('pets, 'orders, 'users) t =
  { pets : 'pets
  ; orders : 'orders
  ; users : 'users
  }

let v ~pets ~orders ~users = { pets; orders; users }
let pets t = t.pets
let orders t = t.orders
let users t = t.users
