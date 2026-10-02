open! Base

(** An abstract JSON Schema fragment indexed by the OCaml type it describes.
    Values are independent of OpenAPI component names and can be used inline by
    parameters, headers, bodies, and responses. *)
type 'a t

(** A schema whose OCaml type index is intentionally hidden. *)
type packed

(** The JSON value shape produced by [ppx_deriving_jsonschema] 0.0.8 on
    native OCaml. Keeping this structural type here lets the core accept
    generated schemas without depending on the PPX runtime. *)
type ppx_schema =
  [ `Null
  | `String of string
  | `Float of float
  | `Int of int
  | `Bool of bool
  | `List of ppx_schema list
  | `Assoc of (string * ppx_schema) list
  ]

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

(** Structural equality that ignores object-member order and preserves array
    order. *)
val equal : 'a t -> 'b t -> bool

(** Structural equality for schemas after their type indices have been erased. *)
val equal_packed : packed -> packed -> bool

(** Erases a schema's OCaml type index for heterogeneous schema collections. *)
val pack : 'a t -> packed

(** Returns the JSON representation used by OpenAPI rendering. *)
val to_yojson : 'a t -> Yojson.Safe.t

(** Returns the JSON representation of an existentially packed schema. *)
val to_yojson_packed : packed -> Yojson.Safe.t

(** Exports a schema for a custom type consumed by the legacy
    [ppx_deriving_jsonschema] PPX. Raises [Invalid_argument] if the value
    contains non-JSON Yojson extensions or an integer literal that does not
    fit into an OCaml [int]. *)
val to_ppx : 'a t -> ppx_schema

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

(** Builds an integer schema whose values use the full OCaml [int64] range. *)
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

(** Allows JSON [null] in addition to [schema]. Applying [nullable] more than
    once has no further effect. *)
val nullable : 'a t -> 'a option t

(** Typed schema-building API used by generated code and public so derived
    schemas can be compiled by downstream applications. *)
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

  (** Adds a JSON Schema format annotation. *)
  val with_format : string -> 'a t -> 'a t

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

  (** Imports a schema emitted by the legacy [ppx_deriving_jsonschema] format. *)
  val of_ppx : ppx_schema -> 'a t
end
