open! Base

module Spec_version : sig
  type t =
    | V3_0_3
    | V3_1_0
    | V3_2_1
end

module Export_error : sig
  type t =
    { path : string
    ; message : string
    }

  val to_string : t -> string
end

(** Converts schema positions only. External resources are never fetched and
    unsupported keywords produce errors rather than weaker schemas. *)
val document
  :  spec_version:Spec_version.t
  -> Yojson.Safe.t
  -> (Yojson.Safe.t, Export_error.t list) Result.t
