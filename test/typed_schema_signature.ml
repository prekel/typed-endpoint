open! Base
open Typed_endpoint

type 'a t = { value : 'a } [@@deriving jsonschema { no_yojson = true }]

let int_schema : int t Json_schema.t = t_jsonschema
let string_schema : string t Json_schema.t = t_jsonschema

type _ phantom = { count : int } [@@deriving jsonschema { no_yojson = true }]
type (_, 'a, _) mixed = { value : 'a } [@@deriving jsonschema { no_yojson = true }]

type _ first = { first : int }
and _ second = { second : string } [@@deriving jsonschema { no_yojson = true }]

type 'a mutable_record = { mutable contents : 'a }
[@@deriving jsonschema { no_yojson = true }]

type 'a ref_alias = 'a ref [@@deriving jsonschema { no_yojson = true }]

let int_phantom_schema : int phantom Json_schema.t = phantom_jsonschema
let mixed_schema : (int, string, bool) mixed Json_schema.t = mixed_jsonschema
let int_mutable_schema : int mutable_record Json_schema.t = mutable_record_jsonschema

let string_mutable_schema : string mutable_record Json_schema.t =
  mutable_record_jsonschema
;;

let int_ref_schema : int ref_alias Json_schema.t = ref_alias_jsonschema
let string_ref_schema : string ref_alias Json_schema.t = ref_alias_jsonschema
