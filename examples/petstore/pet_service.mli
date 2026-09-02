open! Base

type t

val create : unit -> t
val add : t -> Dto.Pet.t -> Dto.Pet.t
val update : t -> Dto.Pet.t -> (Dto.Pet.t, Dto.Api_response.t) Result.t
val find_by_status : t -> string -> Dto.Pet.t list
val find : t -> int -> Dto.Pet.t option
val delete : t -> int -> (unit, Dto.Api_response.t) Result.t
