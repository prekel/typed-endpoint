open! Base
module M = Typed_endpoint_mapper

let id_of_string text =
  match Int.of_string_opt text with
  | Some value when value > 0 -> Ok (Deriver_domain.Id.of_int value)
  | _ ->
    Error (M.Mapping_error.make ~code:"invalid_id" ~message:"expected positive integer")
;;

let status_of_string = function
  | "draft" -> Ok Deriver_domain.Status.Draft
  | "active" -> Ok Deriver_domain.Status.Active
  | _ ->
    Error
      (M.Mapping_error.make ~code:"invalid_status" ~message:"expected draft or active")
;;

let string_of_status : Deriver_domain.Status.t -> string = function
  | Draft -> "draft"
  | Active -> "active"
;;

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

module Checked = struct
  type t =
    { statuses : string list
          [@mapper.from.result fun values -> Ok (List.map values ~f:string_of_status)]
    }
  [@@deriving mapper_from { source = [%type: Deriver_domain.Input.t]; fallible = true }]
end
