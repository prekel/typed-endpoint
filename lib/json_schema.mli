(** JSON Schema fragments indexed by their OCaml wire types. Use the checked
    constructors for handwritten schemas and [typed-endpoint-ppx] for DTOs.
    Constraints describe codecs; they do not add runtime validation. *)

open! Base

(** An abstract JSON Schema fragment indexed by the OCaml type it describes.
    Values can be used directly by parameters, headers, bodies, and responses.
    OpenAPI documentation may be attached without changing the wire shape. *)
type 'a t

(** Adds or replaces optional OpenAPI documentation while preserving the OCaml
    type index and JSON Schema value. Omitted fields retain their previous values;
    empty descriptions and tag lists explicitly replace them. [schema_name]
    registers a reusable OpenAPI component; compilation validates its name and
    rejects conflicting schemas. OpenAPI documentation is stored separately from
    JSON Schema keywords and is not emitted by {!to_yojson}. It does not add
    runtime validation.

    Settings belong to this schema root. Embedding a decorated schema as a
    collection item or DTO field does not register its OpenAPI component by
    itself. Constructors for a new wire type, such as {!list} or {!nullable},
    start with empty OpenAPI metadata; decorate their result when needed. *)
val with_openapi
  :  ?schema_name:string
  -> ?description:string
  -> ?tags:string list
  -> 'a t
  -> 'a t

(** Optional OpenAPI component identity. *)
val schema_name : _ t -> string option

(** OpenAPI description: an explicit override, otherwise the root JSON Schema
    [description] annotation, otherwise the empty string. *)
val description : _ t -> string

(** OpenAPI classification tags; empty by default. *)
val tags : _ t -> string list

(** A schema whose OCaml type index is intentionally hidden. *)
type packed

(** Standard JSON Schema and OpenAPI string formats. [`Custom name] preserves
    extensibility while making all built-in choices typo-safe. *)
type string_format =
  [ `Binary
  | `Byte
  | `Date
  | `Date_time
  | `Duration
  | `Email
  | `Hostname
  | `Idn_email
  | `Idn_hostname
  | `Ipv4
  | `Ipv6
  | `Iri
  | `Iri_reference
  | `Json_pointer
  | `Password
  | `Regex
  | `Relative_json_pointer
  | `Time
  | `Uri
  | `Uri_reference
  | `Uri_template
  | `Uuid
  | `Custom of string
  ]

(** Standard OpenAPI integer formats. *)
type integer_format =
  [ `Int32
  | `Int64
  | `Custom of string
  ]

(** Standard OpenAPI number formats. *)
type number_format =
  [ `Double
  | `Float
  | `Custom of string
  ]

(** A schema accepting every JSON value. *)
val any : Yojson.Safe.t t

(** A schema accepting only JSON [null]. *)
val null : unit t

(** Structural equality of JSON Schema values that ignores object-member order
    and preserves array order. OpenAPI documentation is ignored. *)
val equal : 'a t -> 'b t -> bool

(** Structural equality for schemas after their type indices have been erased. *)
val equal_packed : packed -> packed -> bool

(** Erases a schema's OCaml type index for heterogeneous schema collections. *)
val pack : 'a t -> packed

(** Returns the JSON representation used by OpenAPI rendering. *)
val to_yojson : 'a t -> Yojson.Safe.t

(** Returns the JSON representation of an existentially packed schema. *)
val to_yojson_packed : packed -> Yojson.Safe.t

(** Builds a string schema. A [`Custom format] must be non-empty, lengths must
    be non-negative and ordered, [enum] must be non-empty without duplicates,
    and [default] must belong to [enum] when both are present. *)
val string
  :  ?format:string_format
  -> ?enum:string list
  -> ?min_length:int
  -> ?max_length:int
  -> ?default:string
  -> unit
  -> (string t, string) Result.t

(** The throwing form of {!string}. Invalid arguments raise [Invalid_argument]. *)
val string_exn
  :  ?format:string_format
  -> ?enum:string list
  -> ?min_length:int
  -> ?max_length:int
  -> ?default:string
  -> unit
  -> string t

(** Builds an integer schema. A [`Custom format] must be non-empty, bounds must
    be ordered, and [default] must fall within them. *)
val integer
  :  ?format:integer_format
  -> ?minimum:int
  -> ?maximum:int
  -> ?default:int
  -> unit
  -> (int t, string) Result.t

(** The throwing form of {!integer}. Invalid arguments raise
    [Invalid_argument]. *)
val integer_exn
  :  ?format:integer_format
  -> ?minimum:int
  -> ?maximum:int
  -> ?default:int
  -> unit
  -> int t

(** Builds an integer schema whose bounds and default use the full OCaml
    [int64] range. Bounds must be ordered and contain [default]; a custom format
    must be non-empty. Invalid arguments return [Error]. *)
val int64
  :  ?format:integer_format
  -> ?minimum:int64
  -> ?maximum:int64
  -> ?default:int64
  -> unit
  -> (int64 t, string) Result.t

(** Throwing form of {!int64}; invalid bounds raise [Invalid_argument]. *)
val int64_exn
  :  ?format:integer_format
  -> ?minimum:int64
  -> ?maximum:int64
  -> ?default:int64
  -> unit
  -> int64 t

(** Builds a number schema. A [`Custom format] must be non-empty. Bounds and
    [default] must be finite and ordered, and [default] must fall within them. *)
val number
  :  ?format:number_format
  -> ?minimum:float
  -> ?maximum:float
  -> ?default:float
  -> unit
  -> (float t, string) Result.t

(** The throwing form of {!number}. Invalid arguments raise [Invalid_argument]. *)
val number_exn
  :  ?format:number_format
  -> ?minimum:float
  -> ?maximum:float
  -> ?default:float
  -> unit
  -> float t

(** Builds a boolean schema with an optional documented default. *)
val boolean : ?default:bool -> unit -> bool t

(** Builds an array schema. Item bounds must be non-negative and ordered. *)
val array
  :  ?min_items:int
  -> ?max_items:int
  -> items:'a t
  -> unit
  -> ('a array t, string) Result.t

(** Builds an array schema indexed by an OCaml list. *)
val list
  :  ?min_items:int
  -> ?max_items:int
  -> items:'a t
  -> unit
  -> ('a list t, string) Result.t

(** The throwing form of {!array}. Invalid arguments raise [Invalid_argument]. *)
val array_exn : ?min_items:int -> ?max_items:int -> items:'a t -> unit -> 'a array t

(** Throwing form of {!list}; invalid item bounds raise [Invalid_argument]. *)
val list_exn : ?min_items:int -> ?max_items:int -> items:'a t -> unit -> 'a list t

(** An object whose arbitrary property values conform to [values]. *)
val dictionary : values:'a t -> (string * 'a) list t

(** Allows JSON [null] in addition to the supplied schema. Repeated application
    does not add redundant nullable branches to the JSON Schema value. The new
    option type starts with empty OpenAPI metadata; use {!with_openapi} on the
    result to give the nullable schema its own component name or description. *)
val nullable : 'a t -> 'a option t

(** Adds an opaque JSON annotation without changing the schema's type index or
    validation semantics. [name] must start with [x-], have a non-empty suffix,
    and contain no whitespace. [value] must contain only JSON values, with
    finite floats and valid integer literals. An existing annotation with the
    same name is replaced. OpenAPI rendering preserves the value verbatim,
    including any references it contains. *)
val with_extension : name:string -> value:Yojson.Safe.t -> 'a t -> ('a t, string) Result.t

(** Throwing form of {!with_extension}; invalid arguments raise
    [Invalid_argument]. *)
val with_extension_exn : name:string -> value:Yojson.Safe.t -> 'a t -> 'a t

(** Schema-building support for generated code, exported so downstream derived
    schemas can compile. Several constructors have polymorphic result indices:
    generated code must tie these to the source OCaml type. Handwritten schemas
    should prefer the checked constructors above. *)
module Deriver : sig
  (** Primitive JSON Schema types used by the generated schema builders. *)
  type schema_type =
    | Array
    | Boolean
    | Integer
    | Null
    | Number
    | Object
    | String

  (** Policy for object properties not listed explicitly. *)
  type additional_properties =
    | Allow (** Accept any additional property value. *)
    | Deny (** Reject every unlisted property. *)
    | Schema of packed (** Validate each unlisted property against this schema. *)

  (** Builds a primitive type schema. *)
  val type_schema : schema_type -> 'a t

  (** Builds a string constant schema. *)
  val const_string : string -> 'a t

  (** Builds a reference to a named definition beneath the schema root. *)
  val type_ref : string -> 'a t

  (** Builds a homogeneous array schema. *)
  val array : items:packed -> 'a t

  (** Builds a positional tuple schema. *)
  val tuple : packed list -> 'a t

  (** Accepts a value matching at least one listed schema. *)
  val any_of : packed list -> 'a t

  (** Accepts a value matching exactly one listed schema. *)
  val one_of : packed list -> 'a t

  (** Builds an object schema with named properties and an explicit
      additional-properties policy. *)
  val record
    :  properties:(string * packed) list
    -> required:string list
    -> additional_properties:additional_properties
    -> 'a t

  (** Attaches named definitions to a root reference. Duplicate names keep the
      first definition, so definitions local to the referring schema take
      precedence over imported ones. *)
  val root_ref : root:string -> definitions:(string * packed) list -> 'a t

  (** Returns definitions attached to a schema root, or an empty list. *)
  val definitions : 'a t -> (string * packed) list

  (** Removes root definitions while preserving the root schema. *)
  val without_definitions : 'a t -> 'a t

  (** Adds definitions to the root, keeping existing definitions first. *)
  val with_definitions : (string * packed) list -> 'a t -> 'a t

  (** Adds or replaces the schema identifier. *)
  val with_id : string -> 'a t -> 'a t

  (** Adds a human-readable title annotation. *)
  val with_title : string -> 'a t -> 'a t

  (** Adds a human-readable description annotation. *)
  val with_description : string -> 'a t -> 'a t

  (** Adds a string format annotation without changing the type index, including
      for bytes and nullable strings. A blank [`Custom] name raises
      [Invalid_argument]. Generated code checks the wire type before calling. *)
  val with_string_format_exn : string_format -> 'a t -> 'a t

  (** Adds an integer format annotation. A blank [`Custom] name raises
      [Invalid_argument]. Generated code checks the wire type before calling. *)
  val with_integer_format_exn : integer_format -> 'a t -> 'a t

  (** Adds a number format annotation. A blank [`Custom] name raises
      [Invalid_argument]. Generated code checks the wire type before calling. *)
  val with_number_format_exn : number_format -> 'a t -> 'a t

  (** Adds an inclusive integer lower bound. *)
  val with_minimum_int : int -> 'a t -> 'a t

  (** Adds an inclusive numeric lower bound. *)
  val with_minimum_number : float -> 'a t -> 'a t

  (** Adds an inclusive integer upper bound. *)
  val with_maximum_int : int -> 'a t -> 'a t

  (** Adds an inclusive numeric upper bound. *)
  val with_maximum_number : float -> 'a t -> 'a t

  (** Adds string length bounds. Supplied bounds must be non-negative. *)
  val with_string_lengths : ?minimum:int -> ?maximum:int -> 'a t -> 'a t

  (** Adds a default JSON value after validating that it contains only JSON
      values. *)
  val with_default : Yojson.Safe.t -> 'a t -> 'a t
end

(** Deliberately unchecked escape hatches for schemas not expressible with the
    typed constructors. Prefer the regular constructors whenever possible. *)
module Unsafe : sig
  (** Imports an unchecked JSON value. Use only for schemas that cannot be
      expressed by the safe constructors. Integer literals are preserved;
      non-JSON Yojson extensions are rejected. *)
  val of_yojson : Yojson.Safe.t -> 'a t
end
