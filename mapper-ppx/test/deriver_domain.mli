open! Base

module Id : sig
  type t

  val of_int : int -> t
  val to_string : t -> string
end

module Status : sig
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

module Input : sig
  type t =
    { project_id : Id.t
    ; title : string
    ; priority : int
    ; statuses : Status.t list
    }
end
