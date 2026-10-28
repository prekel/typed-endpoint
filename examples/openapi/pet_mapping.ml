open! Base

let of_domain ({ id; name } : Domain.t) : Generated_api.Dto.Pet.t =
  { id; name; note = Generated_api.Support.Absent }
;;

let to_domain ({ id; name; _ } : Generated_api.Dto.Pet.t) : Domain.t = { id; name }
