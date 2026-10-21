open! Base
open Typed_endpoint

let schema = Json_schema.contramap (Json_schema.string ()) ~f:Int.succ
