open! Base

type status =
  | Draft
  | Live

type t =
  { id : string [@mapper.from.convert Deriver_domain.Id.to_string]
  ; name : string [@mapper.from.field "title"]
  ; status : status [@mapper.from.convert status_of_domain]
  ; revision : int
  ; display : string
        [@mapper.from.compute fun (entity : Deriver_domain.t) -> entity.title ^ "!"]
  }
[@@deriving mapper_from { source = [%type: Deriver_domain.t] }]

type brief = { name : string [@mapper.from.field "title"] }
[@@deriving mapper_from { source = [%type: Deriver_domain.t] }]
