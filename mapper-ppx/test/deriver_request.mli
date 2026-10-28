open! Base
module M = Typed_endpoint_mapper

type t =
  { id : string
        [@mapper.from.field "project_id"]
        [@mapper.from.convert Deriver_domain.Id.to_string]
        [@mapper.into.field "project_id"]
        [@mapper.into.result id_of_string]
  ; name : string [@mapper.from.field "title"] [@mapper.into.field "title"]
  ; priority : int [@mapper.into.convert Int.abs]
  ; statuses : string list
        [@mapper.from.convert List.map ~f:string_of_status]
        [@mapper.into.result M.Converter.list status_of_string]
  ; display : string
        [@mapper.from.compute
          fun (source : Deriver_domain.Input.t) -> String.uppercase source.title]
        [@mapper.into.skip]
  }
[@@deriving
  mapper_from { source = [%type: Deriver_domain.Input.t] }
, mapper_into { target = [%type: Deriver_domain.Input.t]; fallible = true }]

module Checked : sig
  type t =
    { statuses : string list
          [@mapper.from.result fun values -> Ok (List.map values ~f:string_of_status)]
    }
  [@@deriving mapper_from { source = [%type: Deriver_domain.Input.t]; fallible = true }]
end
