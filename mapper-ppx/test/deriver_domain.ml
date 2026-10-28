open! Base

module Id = struct
  type t = int

  let of_int value = value
  let to_string = Int.to_string
end

module Status = struct
  type t =
    | Draft
    | Active
end

type t =
  { id : Id.t
  ; title : string
  ; status : Status.t
  ; revision : int
  ; internal_note : string
  }
