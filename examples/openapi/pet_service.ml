open! Base

let find ~pets id = List.find pets ~f:(fun (pet : Domain.t) -> Int64.equal pet.id id)
