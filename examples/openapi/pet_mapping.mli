open! Base

(** The domain model intentionally excludes the transport-only note. *)
val of_domain : Domain.t -> Generated_api.Dto.Pet.t

val to_domain : Generated_api.Dto.Pet.t -> Domain.t
