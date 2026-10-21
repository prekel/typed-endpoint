(** JSON Schema fragments indexed by their OCaml wire types. Use the checked
    constructors for handwritten schemas and [typed-endpoint-ppx] for DTOs.
    User-facing constructors return schemas directly and raise {!Invalid_schema}
    for invalid declarations. Constraints describe codecs; they do not add
    runtime validation. *)

open! Base

(** An abstract JSON Schema fragment indexed by the OCaml type it describes.
    Values can be used directly by parameters, headers, bodies, and responses.
    OpenAPI documentation may be attached without changing the wire shape. *)
type 'a t

(** A declaration has invalid arguments or conflicting local definitions.
    The payload is a diagnostic, not a rejected runtime request. A printer is
    registered at module initialization for [Stdlib.Printexc.to_string] and
    uncaught-exception reporting, using the public exception name. Exceptions
    raised by user-provided encoders propagate unchanged. *)
exception Invalid_schema of string

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

(** Policy for properties not matched by [properties] or [patternProperties]. *)
type additional_properties =
  | Allow (** Accept any additional property value. *)
  | Deny (** Reject every unmatched property. *)
  | Schema of packed (** Check unmatched values against this schema. *)

(** Describes ['b] using its representation ['a]. [f] witnesses the representation
    used by the application's codec; it is not called or stored. The codec must
    emit the same JSON as encoding [f value] with the original representation.
    The JSON Schema and all OpenAPI metadata are preserved. This does not derive
    a codec or validate values. *)
val contramap : 'a t -> f:('b -> 'a) -> 'b t

(** Uses the schema with JSON values directly. Unlike {!pack}, the result can be
    combined with other schemas indexed by [Yojson.Safe.t]. Metadata is preserved. *)
val as_json : 'a t -> Yojson.Safe.t t

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

(** A schema accepting no JSON value, also usable as [items] to forbid an array
    tail after [prefixItems]. *)
val never : Yojson.Safe.t t

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

(** Exports a DTO schema for json-schema-to-typescript 16.0.0. Tuples use legacy
    [items] arrays, local resources are bundled into [definitions], and boolean
    roots or definitions use [tsType] hints. This is generator input, not a
    general dialect conversion. The ordinary JSON Schema and OpenAPI output
    are unchanged. Only schema positions are rewritten; defaults and literals
    are preserved. Type parameters and unrestricted JSON remain [unknown].

    Returns an error for unresolved references, relative resource identifiers,
    dynamic or anchored scopes, and tuple closures that cannot be lowered
    safely. External references are never fetched. *)
val to_yojson_for_typescript : 'a t -> (Yojson.Safe.t, string) Result.t

(** Returns the JSON representation of an existentially packed schema. *)
val to_yojson_packed : packed -> Yojson.Safe.t

(** Builds a string schema. A [`Custom format] and [content_encoding] must be non-empty, lengths must
    be non-negative and ordered, [enum] must be non-empty without duplicates,
    and [default] must belong to [enum] when both are present. [pattern] is an
    ECMA-262 regular expression, emitted literally without implicit anchoring or
    syntax validation. [content_encoding] documents the encoding (e.g. ["base64"])
    and does not perform it. *)
val string
  :  ?format:string_format
  -> ?enum:string list
  -> ?min_length:int
  -> ?max_length:int
  -> ?pattern:string
  -> ?content_encoding:string
  -> ?default:string
  -> unit
  -> string t

(** Builds an integer schema. A [`Custom format] must be non-empty, bounds must
    be ordered and admit a non-empty numeric interval, and [default] must fall
    within them. [multiple_of] must be strictly positive. Inclusive and exclusive
    bounds may be combined; the strongest bound on each side applies. Default
    validation checks bounds, not divisibility. *)
val integer
  :  ?format:integer_format
  -> ?minimum:int
  -> ?maximum:int
  -> ?exclusive_minimum:int
  -> ?exclusive_maximum:int
  -> ?multiple_of:int
  -> ?default:int
  -> unit
  -> int t

(** Builds an integer schema whose bounds and default use the full OCaml
    [int64] range. Bounds must be ordered and contain [default]; a custom format
    must be non-empty. Strict bounds and [multiple_of] follow {!integer} without
    converting arguments to floating point. Invalid arguments raise {!Invalid_schema}. *)
val int64
  :  ?format:integer_format
  -> ?minimum:int64
  -> ?maximum:int64
  -> ?exclusive_minimum:int64
  -> ?exclusive_maximum:int64
  -> ?multiple_of:int64
  -> ?default:int64
  -> unit
  -> int64 t

(** Builds a number schema. A [`Custom format] must be non-empty. Bounds and
    [default] must be finite and ordered, and [default] must fall within them.
    Exclusive bounds must also be finite, and [multiple_of] must be finite and
    strictly positive. Default validation checks bounds, not divisibility. *)
val number
  :  ?format:number_format
  -> ?minimum:float
  -> ?maximum:float
  -> ?exclusive_minimum:float
  -> ?exclusive_maximum:float
  -> ?multiple_of:float
  -> ?default:float
  -> unit
  -> float t

(** Builds a boolean schema with an optional documented default. *)
val boolean : ?default:bool -> unit -> bool t

(** Builds an array schema. Item and occurrence bounds must be non-negative and
    ordered. [prefix_items], if supplied, must be non-empty; each schema checks
    its position and [items] checks only the remaining tail. The prefix does not
    impose a minimum length. [min_contains] and [max_contains] require [contains];
    its effective minimum is one unless explicitly overridden, including zero.
    Prefix, tail and [contains] share the element index. Use {!as_json} for
    heterogeneous elements. Local definition conflicts raise {!Invalid_schema}. *)
val array
  :  ?min_items:int
  -> ?max_items:int
  -> ?prefix_items:'a t list
  -> ?unique_items:bool
  -> ?contains:'a t
  -> ?min_contains:int
  -> ?max_contains:int
  -> items:'a t
  -> unit
  -> 'a array t

(** Builds an array schema indexed by an OCaml list. *)
val list
  :  ?min_items:int
  -> ?max_items:int
  -> ?prefix_items:'a t list
  -> ?unique_items:bool
  -> ?contains:'a t
  -> ?min_contains:int
  -> ?max_contains:int
  -> items:'a t
  -> unit
  -> 'a list t

(** An object whose arbitrary property values conform to [values]. *)
val dictionary : values:'a t -> (string * 'a) list t

(** Allows JSON [null] in addition to the supplied schema. Repeated application
    does not add redundant nullable branches to the JSON Schema value. The new
    option type starts with empty OpenAPI metadata; use {!with_openapi} on the
    result to give the nullable schema its own component name or description. *)
val nullable : 'a t -> 'a option t

(** Intersection of a non-empty list of schemas sharing a representation.
    Local definitions without their own [$id] are lifted to the result root;
    conflicting definitions raise {!Invalid_schema}. Separate [$id] resources retain
    their scopes. New compositions start without OpenAPI metadata. *)
val all_of : 'a t list -> 'a t

(** Union of a non-empty list of schemas sharing a representation. Definition
    handling and metadata follow {!all_of}; use {!as_json} for mixed types. *)
val any_of : 'a t list -> 'a t

(** Requires exactly one matching branch. The list must be non-empty; definition
    handling and metadata follow {!all_of}. *)
val one_of : 'a t list -> 'a t

(** Complements a schema. The result uses JSON values because a complement can
    accept types outside the original OCaml representation. *)
val not_ : 'a t -> Yojson.Safe.t t

(** Excludes values matching [schema] from the supplied base schema, preserving
    the base type, constraints and OpenAPI metadata. *)
val with_not : schema:'b t -> 'a t -> 'a t

(** Selects [then_] when [if_] matches, otherwise [else_]. Both branches use the
    same representation. Definitions and metadata follow {!all_of}. *)
val if_then_else : if_:'b t -> then_:'a t -> else_:'a t -> 'a t

(** Builds a schema for JSON objects directly, without claiming an arbitrary
    OCaml record representation. Unmatched properties are allowed by default.
    Names in each map and [required] must be unique; property-count bounds must
    be non-negative and ordered. [property_names] checks key strings, while
    [pattern_properties] checks values for every matching ECMA-262 pattern.
    Patterns are emitted literally without syntax validation. [dependent_required]
    requires the listed keys when its triggering key is present;
    [dependent_schemas] checks the whole object when its key is present.
    Definition handling and metadata follow {!all_of}. *)
val object_
  :  ?properties:(string * packed) list
  -> ?required:string list
  -> ?additional_properties:additional_properties
  -> ?property_names:string t
  -> ?pattern_properties:(string * packed) list
  -> ?min_properties:int
  -> ?max_properties:int
  -> ?dependent_required:(string * string list) list
  -> ?dependent_schemas:(string * packed) list
  -> unit
  -> Yojson.Safe.t t

(** Adds object constraints without weakening the dictionary's value schema.
    Pattern-matched values must satisfy both the original value schema and every
    matching pattern schema. Existing constraints and metadata are preserved.
    Argument checks follow {!object_}. *)
val with_dictionary_constraints
  :  ?property_names:string t
  -> ?pattern_properties:(string * 'a t) list
  -> ?min_properties:int
  -> ?max_properties:int
  -> ?dependent_required:(string * string list) list
  -> ?dependent_schemas:(string * packed) list
  -> (string * 'a) list t
  -> (string * 'a) list t

(** Restricts the existing schema to the encoded values, including whole arrays
    or objects. [encode] must use the application's wire representation. The
    list must be non-empty and its encoded JSON values must be distinct (object
    order and numeric spelling do not distinguish values). Non-finite floats,
    invalid integer literals and duplicate object members raise {!Invalid_schema}. This
    does not check literals against the schema or derive runtime validation.
    Encoder exceptions propagate. Metadata and existing constraints are preserved. *)
val with_enum : encode:('a -> Yojson.Safe.t) -> 'a list -> 'a t -> 'a t

(** Restricts the schema to one encoded value. Encoding, validation and metadata
    follow {!with_enum}. *)
val with_const : encode:('a -> Yojson.Safe.t) -> 'a -> 'a t -> 'a t

(** Adds or replaces the JSON Schema title, preserving OpenAPI metadata. *)
val with_title : string -> 'a t -> 'a t

(** Adds or replaces the JSON Schema description. An explicit description from
    {!with_openapi} retains precedence. *)
val with_description : string -> 'a t -> 'a t

(** Adds or replaces the deprecation annotation without changing validation. *)
val with_deprecated : bool -> 'a t -> 'a t

(** Documents ownership of a value; does not change codecs or requiredness. *)
val with_read_only : bool -> 'a t -> 'a t

(** Documents a value intended for writes; does not change codecs or requiredness. *)
val with_write_only : bool -> 'a t -> 'a t

(** Adds or replaces encoded examples. JSON validation follows {!with_enum},
    except an empty list and repeated examples are allowed. *)
val with_examples : encode:('a -> Yojson.Safe.t) -> 'a list -> 'a t -> 'a t

(** Adds or replaces an explicit OpenAPI discriminator on [allOf], [anyOf] or
    [oneOf]. Mapping keys must be unique; targets are preserved verbatim and
    are not registered or resolved. The caller must provide object branches
    with the discriminator property and appropriate schema references; this
    does not transform Yojson variants or derive a codec. Metadata is preserved. *)
val with_discriminator
  :  property_name:string
  -> ?mapping:(string * string) list
  -> 'a t
  -> 'a t

(** Adds an opaque JSON annotation without changing the schema's type index or
    validation semantics. [name] must start with [x-], have a non-empty suffix,
    and contain no whitespace. [value] must contain only JSON values, with
    finite floats and valid integer literals. An existing annotation with the
    same name is replaced. OpenAPI rendering preserves the value verbatim,
    including any references it contains. *)
val with_extension : name:string -> value:Yojson.Safe.t -> 'a t -> 'a t

(** Schema-building support for generated code, exported so downstream derived
    schemas can compile. Several constructors have polymorphic result indices:
    generated code must tie these to the source OCaml type. Handwritten schemas
    should prefer the checked constructors above. *)
module Deriver : sig
  (** An immutable schema with a universally quantified type index. Generated
      code projects [schema] through a stable binding to generalize schema
      constants even when the DTO has invariant type parameters. *)
  type polymorphic = { schema : 'a. 'a t }

  (** Erases the index while preserving the schema and all metadata. This is
      only for derived schemas whose type parameters have already been replaced
      with unrestricted JSON schemas; the generated binding must constrain the
      projected value to the declared DTO type. *)
  val polymorphic : packed -> polymorphic

  (** An unrestricted schema for a type parameter whose codec is unknown. *)
  val any : 'a t

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
  type nonrec additional_properties = additional_properties =
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
