open! Base
open Typed_endpoint

type 'a t = { value : 'a } [@@deriving jsonschema]

let int_schema = t_jsonschema (Json_schema.integer_exn ())
