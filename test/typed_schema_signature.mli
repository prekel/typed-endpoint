(** Signature fixture for schema constants that retain their DTO type indices
    while generalizing all type parameters. *)

open! Base
open Typed_endpoint

(** Generic DTO shape used to check the type index of generated schemas. *)
type 'a t = { value : 'a } [@@deriving jsonschema { no_yojson = true }]

(** Schema specialization for integer payloads. *)
val int_schema : int t Json_schema.t

(** The same schema constant also describes string payloads. *)
val string_schema : string t Json_schema.t

(** Anonymous parameters are generalized without schema arguments. *)
type _ phantom = { count : int } [@@deriving jsonschema { no_yojson = true }]

(** Named and anonymous parameters retain their result type indices. *)
type (_, 'a, _) mixed = { value : 'a } [@@deriving jsonschema { no_yojson = true }]

(** Anonymous parameters also work in declaration groups. *)
type _ first = { first : int }

and _ second = { second : string } [@@deriving jsonschema { no_yojson = true }]

(** Invariant parameters must generalize despite allocating a schema. *)
type 'a mutable_record = { mutable contents : 'a }
[@@deriving jsonschema { no_yojson = true }]

(** Reference aliases also have invariant parameters. *)
type 'a ref_alias = 'a ref [@@deriving jsonschema { no_yojson = true }]

(** Schema specialization for an anonymous integer parameter. *)
val int_phantom_schema : int phantom Json_schema.t

(** Schema specialization with distinct types for all three parameters. *)
val mixed_schema : (int, string, bool) mixed Json_schema.t

(** The mutable record's schema is reusable with distinct parameter types. *)
val int_mutable_schema : int mutable_record Json_schema.t

val string_mutable_schema : string mutable_record Json_schema.t

(** The reference alias's schema is reusable with distinct parameter types. *)
val int_ref_schema : int ref_alias Json_schema.t

val string_ref_schema : string ref_alias Json_schema.t
