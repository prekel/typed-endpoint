open! Base
open Typed_endpoint

module Ppx_string = struct
  type t = string [@@deriving jsonschema]
end

module Ppx_integer = struct
  type t = int [@@deriving jsonschema]
end

module Ppx_number = struct
  type t = float [@@deriving jsonschema]
end

module Ppx_boolean = struct
  type t = bool [@@deriving jsonschema]
end

module Ppx_array = struct
  type t = string list [@@deriving jsonschema]
end

module Ppx_nullable = struct
  type t = string option [@@deriving jsonschema]
end

module Ppx_bounded_integer = struct
  type t = int [@@jsonschema.minimum 1] [@@jsonschema.maximum 100] [@@deriving jsonschema]
end

module Ppx_formatted_string = struct
  type t = string [@@jsonschema.format `Date_time] [@@deriving jsonschema]
end

module Ppx_formats = struct
  type t =
    { uuid : string [@jsonschema.format `Uuid]
    ; date : string option [@jsonschema.attrs { format = `Date_time }]
    ; binary : bytes [@jsonschema.format `Binary]
    ; integer : Int32.t [@jsonschema.format `Int32]
    ; wide : int64 option [@jsonschema.format `Int64]
    ; number : float [@jsonschema.attrs { format = `Double }]
    ; vendor_string : string [@jsonschema.format `Custom "my-format"]
    ; vendor_integer : int [@jsonschema.attrs { format = `Custom "vendor-integer" }]
    ; vendor_number : float option [@jsonschema.format `Custom "vendor-number"]
    ; encoded : (int64[@encoding `string]) [@jsonschema.format `Custom "decimal"]
    ; nested : (string[@jsonschema.format `Email]) option
    }
  [@@deriving yojson, jsonschema]
end

module Ppx_annotated_group = struct
  type count = int
  [@@jsonschema.format `Int32] [@@jsonschema.attrs { minimum = 0; maximum = 100 }]

  and measure = float
  [@@jsonschema.attrs { format = `Float; title = "Measure" }] [@@deriving jsonschema]
end

module Ppx_annotated_recursive_group = struct
  type count = int [@@jsonschema.attrs { format = `Int64; minimum = 0 }]

  and node =
    { count : count
    ; next : node option
    }
  [@@jsonschema.title "Node"] [@@deriving jsonschema]
end

module Ppx_outer_annotations = struct
  type t = { value : (string[@jsonschema.title "Inner"]) [@jsonschema.title "Outer"] }
  [@@deriving jsonschema]
end

module Ppx_doc_annotations = struct
  (** Record documentation. *)
  type t =
    { fallback : string (** Field documentation. *)
    ; explicit : string [@jsonschema.description "Explicit description"]
      (** Ignored field documentation. *)
    ; attrs : string [@jsonschema.attrs { description = "Attrs description" }]
      (** Ignored attrs documentation. *)
    }
  [@@deriving jsonschema { ocaml_doc }]
end

module Ppx_wire_annotations = struct
  type t = { display_name : string option [@key "displayName"] [@default None] }
  [@@deriving yojson, jsonschema { strict = true }]
end

module Ppx_generic = struct
  type 'a t = { value : 'a } [@@deriving jsonschema]
end

module Ppx_yojson_permissive = struct
  type t = { value : int }
  [@@deriving yojson { strict = false }, jsonschema { strict = false }]
end

module Ppx_yojson_default_strict = struct
  type t = { value : int } [@@deriving yojson, jsonschema]
end

module Ppx_default_record = struct
  type t = { value : int } [@@deriving jsonschema]
end

module Ppx_disallow_extra_fields = struct
  type t = { value : int } [@@deriving jsonschema] [@@jsonschema.disallow_extra_fields]
end

module Ppx_allow_extra_fields = struct
  type t = { value : int }
  [@@deriving jsonschema { strict = true }] [@@jsonschema.allow_extra_fields]
end

module Ppx_strict_option = struct
  type t = { value : int } [@@deriving jsonschema { strict = true }]
end

module Ppx_inline_record_extra_fields = struct
  type t =
    | Strict of { value : int } [@jsonschema.disallow_extra_fields]
    | Permissive of { value : int }
  [@@deriving jsonschema]
end

module Ppx_named_variant = struct
  type t =
    | Empty [@name "none"]
    | Value of int [@name "value"]
  [@@deriving yojson, jsonschema]
end

module Ppx_custom_default = struct
  type amount = int64 [@@deriving yojson]

  let amount_jsonschema = Json_schema.int64 ()

  (* Yojson's default strict decoder closes record schemas. *)
  type t = { amount : amount [@default 9223372036854775807L] }
  [@@deriving yojson, jsonschema]
end

module Ppx_title_attribute = struct
  type t = { name : string [@jsonschema.title "Display name"] }
  [@@deriving jsonschema] [@@jsonschema.title "Pet"]
end

module Ppx_title_attrs = struct
  type t =
    { name : string
          [@jsonschema.attrs { title = "Display name"; description = "Name in the API" }]
    }
  [@@deriving jsonschema]
end

module Ppx_option_alias = struct
  type maybe_string = string option [@@deriving yojson, jsonschema]
  type required_alias = { value : maybe_string } [@@deriving yojson, jsonschema]

  type optional_alias = { value : maybe_string [@default None] }
  [@@deriving yojson, jsonschema]
end

module Ppx_cross_module_dependency = struct
  type t = { node : Schema_dependency.node } [@@deriving jsonschema]
end

let print_schema schema =
  Json_schema.to_yojson schema |> Yojson.Safe.pretty_to_string |> Stdlib.print_endline
;;

let print_if_equal smart ppx =
  if not (Json_schema.equal smart ppx) then
    Stdlib.failwith
      ("smart schema differs from PPX schema:\n"
       ^ Yojson.Safe.pretty_to_string (Json_schema.to_yojson smart)
       ^ "\n<->\n"
       ^ Yojson.Safe.pretty_to_string (Json_schema.to_yojson ppx));
  print_schema smart
;;

let%expect_test "primitive smart constructors agree with PPX schemas" =
  print_if_equal (Json_schema.string ()) Ppx_string.t_jsonschema;
  [%expect {| { "type": "string" } |}];
  print_if_equal (Json_schema.integer ()) Ppx_integer.t_jsonschema;
  [%expect {| { "type": "integer" } |}];
  print_if_equal (Json_schema.number ()) Ppx_number.t_jsonschema;
  [%expect {| { "type": "number" } |}];
  print_if_equal (Json_schema.boolean ()) Ppx_boolean.t_jsonschema;
  [%expect {| { "type": "boolean" } |}]
;;

let%expect_test "composed smart constructors agree with PPX schemas" =
  print_if_equal
    (Json_schema.array ~items:(Json_schema.string ()) ())
    Ppx_array.t_jsonschema;
  [%expect {| { "type": "array", "items": { "type": "string" } } |}];
  print_if_equal (Json_schema.nullable (Json_schema.string ())) Ppx_nullable.t_jsonschema;
  [%expect {| { "type": [ "string", "null" ] } |}];
  print_if_equal
    (Json_schema.integer ~minimum:1 ~maximum:100 ())
    Ppx_bounded_integer.t_jsonschema;
  [%expect {| { "type": "integer", "minimum": 1, "maximum": 100 } |}];
  print_if_equal
    (Json_schema.string ~format:`Date_time ())
    Ppx_formatted_string.t_jsonschema;
  [%expect {| { "type": "string", "format": "date-time" } |}]
;;

let%expect_test "formats follow the field wire type" =
  let property name =
    Json_schema.to_yojson Ppx_formats.t_jsonschema
    |> Yojson.Safe.Util.member "properties"
    |> Yojson.Safe.Util.member name
    |> Yojson.Safe.to_string
    |> Stdlib.print_endline
  in
  property "uuid";
  [%expect {| {"format":"uuid","type":"string"} |}];
  property "date";
  [%expect {| {"format":"date-time","type":["string","null"]} |}];
  property "binary";
  [%expect {| {"format":"binary","type":"string"} |}];
  property "integer";
  [%expect {| {"format":"int32","type":"integer"} |}];
  property "wide";
  [%expect {| {"format":"int64","type":["integer","null"]} |}];
  property "number";
  [%expect {| {"format":"double","type":"number"} |}];
  property "vendor_string";
  [%expect {| {"format":"my-format","type":"string"} |}];
  property "vendor_integer";
  [%expect {| {"format":"vendor-integer","type":"integer"} |}];
  property "vendor_number";
  [%expect {| {"format":"vendor-number","type":["number","null"]} |}];
  property "encoded";
  [%expect {| {"format":"decimal","type":"string"} |}];
  property "nested";
  [%expect {| {"format":"email","type":["string","null"]} |}]
;;

let%expect_test "annotations apply to every nonrecursive group member" =
  print_schema Ppx_annotated_group.count_jsonschema;
  [%expect {| { "format": "int32", "maximum": 100, "minimum": 0, "type": "integer" } |}];
  print_schema Ppx_annotated_group.measure_jsonschema;
  [%expect {| { "title": "Measure", "format": "float", "type": "number" } |}]
;;

let%expect_test "recursive definitions preserve each member's annotations" =
  let definitions =
    Json_schema.to_yojson Ppx_annotated_recursive_group.node_jsonschema
    |> Yojson.Safe.Util.member "$defs"
  in
  definitions
  |> Yojson.Safe.Util.member "count"
  |> Yojson.Safe.to_string
  |> Stdlib.print_endline;
  [%expect {| {"minimum":0,"format":"int64","type":"integer"} |}];
  definitions
  |> Yojson.Safe.Util.member "node"
  |> Yojson.Safe.Util.member "title"
  |> Yojson.Safe.to_string
  |> Stdlib.print_endline;
  [%expect {| "Node" |}]
;;

let%expect_test "outer node annotations override inner node annotations" =
  Json_schema.to_yojson Ppx_outer_annotations.t_jsonschema
  |> Yojson.Safe.Util.member "properties"
  |> Yojson.Safe.Util.member "value"
  |> Yojson.Safe.to_string
  |> Stdlib.print_endline;
  [%expect {| {"title":"Outer","type":"string"} |}]
;;

let%expect_test "explicit descriptions override odoc fallback" =
  let schema = Json_schema.to_yojson Ppx_doc_annotations.t_jsonschema in
  let print value = Stdlib.print_endline (Yojson.Safe.to_string value) in
  print (Yojson.Safe.Util.member "description" schema);
  [%expect {| "Record documentation." |}];
  let description name =
    schema
    |> Yojson.Safe.Util.member "properties"
    |> Yojson.Safe.Util.member name
    |> Yojson.Safe.Util.member "description"
    |> print
  in
  description "fallback";
  [%expect {| "Field documentation." |}];
  description "explicit";
  [%expect {| "Explicit description" |}];
  description "attrs";
  [%expect {| "Attrs description" |}]
;;

let%test_unit "Deriver format builders reject blank custom names" =
  let rejects f =
    match f () with
    | _ -> assert false
    | exception Invalid_argument error ->
      assert (String.equal error "format must not be empty")
  in
  rejects (fun () ->
    Json_schema.Deriver.with_string_format_exn (`Custom " ") Json_schema.any);
  rejects (fun () ->
    Json_schema.Deriver.with_integer_format_exn (`Custom "") Json_schema.any);
  rejects (fun () ->
    Json_schema.Deriver.with_number_format_exn (`Custom "\t") Json_schema.any)
;;

let%expect_test "smart schemas have stable JSON output" =
  Json_schema.string
    ~format:`Uuid
    ~enum:[ "primary"; "secondary" ]
    ~min_length:1
    ~max_length:32
    ~default:"primary"
    ()
  |> print_schema;
  [%expect
    {|
    {
      "type": "string",
      "format": "uuid",
      "enum": [ "primary", "secondary" ],
      "minLength": 1,
      "maxLength": 32,
      "default": "primary"
    }
    |}];
  Json_schema.integer ~format:`Int64 ~minimum:1 ~maximum:100 ~default:1 () |> print_schema;
  [%expect
    {|
    {
      "type": "integer",
      "format": "int64",
      "minimum": 1,
      "maximum": 100,
      "default": 1
    }
    |}];
  Json_schema.array ~min_items:1 ~max_items:3 ~items:(Json_schema.string ()) ()
  |> print_schema;
  [%expect
    {|
    {
      "type": "array",
      "items": { "type": "string" },
      "minItems": 1,
      "maxItems": 3
    }
    |}];
  Json_schema.dictionary ~values:(Json_schema.integer ~format:`Int32 ()) |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "additionalProperties": { "type": "integer", "format": "int32" }
    }
    |}]
;;

let%expect_test "Yojson wire annotations produce matching schema" =
  Ppx_wire_annotations.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": {
        "displayName": { "default": null, "type": [ "string", "null" ] }
      },
      "required": [],
      "additionalProperties": false
    }
    |}]
;;

let%expect_test "generic schema is parameterized by its type" =
  Ppx_generic.t_jsonschema (Json_schema.integer ()) |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": { "value": { "type": "integer" } },
      "required": [ "value" ],
      "additionalProperties": true
    }
    |}]
;;

let%expect_test "Yojson strict false permits extra object properties in the schema" =
  Ppx_yojson_permissive.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": { "value": { "type": "integer" } },
      "required": [ "value" ],
      "additionalProperties": true
    }
    |}]
;;

let%expect_test "Yojson default strictness rejects extra object properties in the schema" =
  Ppx_yojson_default_strict.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": { "value": { "type": "integer" } },
      "required": [ "value" ],
      "additionalProperties": false
    }
    |}]
;;

let%test "Yojson strict false decoder ignores extra fields" =
  match
    Ppx_yojson_permissive.of_yojson (`Assoc [ "value", `Int 1; "extra", `Bool true ])
  with
  | Ok { value = 1 } -> true
  | _ -> false
;;

let%expect_test "record schemas allow extra fields by default" =
  Ppx_default_record.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": { "value": { "type": "integer" } },
      "required": [ "value" ],
      "additionalProperties": true
    }
    |}]
;;

let%expect_test "disallow_extra_fields opts a record into strict mode" =
  Ppx_disallow_extra_fields.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": { "value": { "type": "integer" } },
      "required": [ "value" ],
      "additionalProperties": false
    }
    |}]
;;

let%expect_test "allow_extra_fields overrides standalone strict mode" =
  Ppx_allow_extra_fields.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": { "value": { "type": "integer" } },
      "required": [ "value" ],
      "additionalProperties": true
    }
    |}]
;;

let%expect_test "strict option can opt all records into strict mode" =
  Ppx_strict_option.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": { "value": { "type": "integer" } },
      "required": [ "value" ],
      "additionalProperties": false
    }
    |}]
;;

let%expect_test "disallow_extra_fields applies to inline variant records" =
  Ppx_inline_record_extra_fields.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "anyOf": [
        {
          "type": "array",
          "prefixItems": [
            { "const": "Strict" },
            {
              "type": "object",
              "properties": { "value": { "type": "integer" } },
              "required": [ "value" ],
              "additionalProperties": false
            }
          ],
          "unevaluatedItems": false,
          "minItems": 2,
          "maxItems": 2
        },
        {
          "type": "array",
          "prefixItems": [
            { "const": "Permissive" },
            {
              "type": "object",
              "properties": { "value": { "type": "integer" } },
              "required": [ "value" ],
              "additionalProperties": true
            }
          ],
          "unevaluatedItems": false,
          "minItems": 2,
          "maxItems": 2
        }
      ]
    }
    |}]
;;

let%expect_test "variant names follow Yojson name attributes" =
  Ppx_named_variant.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "anyOf": [
        {
          "type": "array",
          "prefixItems": [ { "const": "none" } ],
          "unevaluatedItems": false,
          "minItems": 1,
          "maxItems": 1
        },
        {
          "type": "array",
          "prefixItems": [ { "const": "value" }, { "type": "integer" } ],
          "unevaluatedItems": false,
          "minItems": 2,
          "maxItems": 2
        }
      ]
    }
    |}]
;;

let%expect_test "custom defaults use Yojson serializers and preserve int64" =
  Ppx_custom_default.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": {
        "amount": { "default": 9223372036854775807, "type": "integer" }
      },
      "required": [],
      "additionalProperties": false
    }
    |}]
;;

let%expect_test "title works on a type and a field" =
  Ppx_title_attribute.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "title": "Pet",
      "type": "object",
      "properties": { "name": { "title": "Display name", "type": "string" } },
      "required": [ "name" ],
      "additionalProperties": true
    }
    |}]
;;

let%expect_test "jsonschema.attrs accepts title and description" =
  Ppx_title_attrs.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": {
        "name": {
          "description": "Name in the API",
          "title": "Display name",
          "type": "string"
        }
      },
      "required": [ "name" ],
      "additionalProperties": true
    }
    |}]
;;

let%expect_test "an option alias remains required unless marked optional" =
  Ppx_option_alias.required_alias_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": { "value": { "type": [ "string", "null" ] } },
      "required": [ "value" ],
      "additionalProperties": false
    }
    |}];
  Ppx_option_alias.optional_alias_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": {
        "value": { "default": null, "type": [ "string", "null" ] }
      },
      "required": [],
      "additionalProperties": false
    }
    |}]
;;

let%test "an option alias accepts null but not a missing required field" =
  match
    ( Ppx_option_alias.required_alias_of_yojson (`Assoc [ "value", `Null ])
    , Ppx_option_alias.required_alias_of_yojson (`Assoc []) )
  with
  | Ok { value = None }, Error _ -> true
  | _ -> false
;;

let%test "cross-module recursive schema keeps its definitions with the reference" =
  let schema = Ppx_cross_module_dependency.t_jsonschema |> Json_schema.to_yojson in
  let dependency =
    Yojson.Safe.Util.member "node" (Yojson.Safe.Util.member "properties" schema)
  in
  let definitions = Yojson.Safe.Util.member "$defs" dependency in
  let reference = Yojson.Safe.Util.member "$ref" dependency in
  match definitions, reference with
  | `Assoc [ ("node", `Assoc _) ], `String "#/$defs/node" -> true
  | _ -> false
;;

let%test "recursive schemas give local references their own resource root" =
  match Json_schema.to_yojson Schema_dependency.node_jsonschema with
  | `Assoc fields ->
    (match
       ( List.Assoc.find fields "$id" ~equal:String.equal
       , List.Assoc.find fields "$ref" ~equal:String.equal )
     with
     | Some (`String id), Some (`String "#/$defs/node") ->
       String.is_prefix id ~prefix:"urn:typed-endpoint:schema:"
     | _ -> false)
  | _ -> false
;;

let ordered_schema : unit Json_schema.t =
  Json_schema.Unsafe.of_yojson
    (`Assoc [ "type", `String "array"; "enum", `List [ `Int 1; `Int 2 ] ])
;;

let wide_integer_schema : unit Json_schema.t =
  Json_schema.Unsafe.of_yojson (`Assoc [ "maximum", `Intlit "9223372036854775807" ])
;;

let%test "unsafe JSON schema imports preserve wide integer literals" =
  Json_schema.equal
    wide_integer_schema
    (Json_schema.Unsafe.of_yojson (`Assoc [ "maximum", `Intlit "9223372036854775807" ]))
;;

let%test "schema equality ignores object-member order" =
  Json_schema.equal
    ordered_schema
    (Json_schema.Unsafe.of_yojson
       (`Assoc [ "enum", `List [ `Int 1; `Int 2 ]; "type", `String "array" ]))
;;

let%test "schema equality preserves array order" =
  not
    (Json_schema.equal
       ordered_schema
       (Json_schema.Unsafe.of_yojson
          (`Assoc [ "type", `String "array"; "enum", `List [ `Int 2; `Int 1 ] ])))
;;

let%test "nullable is idempotent" =
  let nullable = Json_schema.nullable (Json_schema.string ()) in
  Json_schema.equal nullable (Json_schema.nullable nullable)
;;

let%test_unit "nullable preserves string enum and const constraints" =
  let enum_schema =
    Json_schema.string ~enum:[ "first"; "second" ] ()
    |> Json_schema.nullable
    |> Json_schema.to_yojson
    |> Yojson.Safe.to_basic
  in
  let const_schema =
    Json_schema.Unsafe.of_yojson (`Assoc [ "const", `String "fixed" ])
    |> Json_schema.nullable
    |> Json_schema.to_yojson
    |> Yojson.Safe.to_basic
  in
  let validator schema =
    match Jsonschema.create_validator_from_json ~schema () with
    | Ok validator -> validator
    | Error error ->
      Stdlib.failwith (Stdlib.Format.asprintf "%a" Jsonschema.pp_compile_error error)
  in
  let enum_validator = validator enum_schema in
  let const_validator = validator const_schema in
  assert (Result.is_ok (Jsonschema.validate enum_validator `Null));
  assert (Result.is_ok (Jsonschema.validate enum_validator (`String "first")));
  assert (Result.is_error (Jsonschema.validate enum_validator (`String "other")));
  assert (Result.is_ok (Jsonschema.validate const_validator `Null));
  assert (Result.is_ok (Jsonschema.validate const_validator (`String "fixed")));
  assert (Result.is_error (Jsonschema.validate const_validator (`String "other")))
;;

let print_error f =
  match f () with
  | _ -> Stdlib.failwith "expected a schema error"
  | exception Json_schema.Invalid_schema error -> Stdlib.print_endline error
;;

let%expect_test "extensions preserve constraints and replace only matching annotations" =
  let original = Json_schema.string ~min_length:1 () in
  let schema =
    original
    |> Json_schema.with_extension ~name:"x-domain" ~value:(`String "pets")
    |> Json_schema.with_extension ~name:"x-version" ~value:(`Int 1)
    |> Json_schema.with_extension ~name:"x-domain" ~value:(`String "owners")
  in
  Json_schema.to_yojson schema |> Yojson.Safe.to_string |> Stdlib.print_endline;
  [%expect {| {"x-domain":"owners","x-version":1,"type":"string","minLength":1} |}];
  Json_schema.to_yojson original |> Yojson.Safe.to_string |> Stdlib.print_endline;
  [%expect {| {"type":"string","minLength":1} |}]
;;

let%expect_test "extension names cannot replace standard schema keywords" =
  let add name =
    print_error (fun () -> Json_schema.with_extension ~name ~value:`Null Json_schema.any)
  in
  add "type";
  [%expect
    {| extension name must start with x-, have a non-empty suffix and no whitespace |}];
  add "x-";
  [%expect
    {| extension name must start with x-, have a non-empty suffix and no whitespace |}];
  add "x-domain name";
  [%expect
    {| extension name must start with x-, have a non-empty suffix and no whitespace |}];
  add "x-domain\n";
  [%expect
    {| extension name must start with x-, have a non-empty suffix and no whitespace |}]
;;

let%expect_test "extension values reject non-finite numbers and invalid integer literals" =
  let add value =
    print_error (fun () ->
      Json_schema.with_extension ~name:"x-domain" ~value Json_schema.any)
  in
  add (`Assoc [ "nested", `List [ `Float Float.nan ] ]);
  [%expect {| extension value must contain only finite floats |}];
  add (`Float Float.infinity);
  [%expect {| extension value must contain only finite floats |}];
  add (`Float Float.neg_infinity);
  [%expect {| extension value must contain only finite floats |}];
  add (`List [ `Intlit "01" ]);
  [%expect {| extension value must contain only valid JSON integer literals |}];
  add (`Intlit "1.5");
  [%expect {| extension value must contain only valid JSON integer literals |}]
;;

let%test_unit "extensions preserve arbitrary JSON values and wide integer literals" =
  let values =
    [ `Null
    ; `Bool false
    ; `Int 7
    ; `Float 1.5
    ; `String "pets"
    ; `Intlit "9223372036854775808"
    ; `Intlit "-9223372036854775809"
    ; `Intlit "0"
    ; `Intlit "-0"
    ; `List [ `String "eq"; `String "and" ]
    ; `Assoc [ "fields", `Assoc [ "name", `Assoc [ "type", `String "string" ] ] ]
    ]
  in
  List.iter values ~f:(fun value ->
    let schema =
      Json_schema.string ()
      |> Json_schema.with_extension ~name:"x-domain" ~value
      |> Json_schema.to_yojson
    in
    assert (Yojson.Safe.equal (Yojson.Safe.Util.member "x-domain" schema) value));
  List.iter [ ""; "-"; "+1"; "-01"; "1e2"; " 1" ] ~f:(fun literal ->
    match
      Json_schema.with_extension ~name:"x-domain" ~value:(`Intlit literal) Json_schema.any
    with
    | _ -> assert false
    | exception Json_schema.Invalid_schema _ -> ())
;;

let%test_unit "extension constructor reports invalid declarations" =
  let raises_invalid_schema f =
    match f () with
    | _ -> assert false
    | exception Json_schema.Invalid_schema _ -> ()
  in
  raises_invalid_schema (fun () ->
    Json_schema.with_extension ~name:"type" ~value:`Null Json_schema.any);
  raises_invalid_schema (fun () ->
    Json_schema.with_extension ~name:"x-domain" ~value:(`Float Float.nan) Json_schema.any)
;;

let%expect_test "extensions preserve boolean schema semantics" =
  let annotated schema =
    Json_schema.with_extension ~name:"x-domain" ~value:`Null schema
  in
  let check schema expected =
    let schema = annotated schema |> Json_schema.to_yojson in
    Yojson.Safe.to_string schema |> Stdlib.print_endline;
    let validator =
      match
        Jsonschema.create_validator_from_json ~schema:(Yojson.Safe.to_basic schema) ()
      with
      | Ok validator -> validator
      | Error error ->
        Stdlib.failwith (Stdlib.Format.asprintf "%a" Jsonschema.pp_compile_error error)
    in
    List.iter
      [ `Null; `String "name"; `Int 7; `Assoc [] ]
      ~f:(fun value ->
        assert (Bool.equal (Result.is_ok (Jsonschema.validate validator value)) expected))
  in
  check Json_schema.any true;
  [%expect {| {"x-domain":null,"allOf":[true]} |}];
  check (Json_schema.Unsafe.of_yojson (`Bool false)) false;
  [%expect {| {"x-domain":null,"allOf":[false]} |}]
;;

let%test_unit "extensions preserve recursive schema definitions and references" =
  let original = Schema_dependency.node_jsonschema in
  let annotated =
    original |> Json_schema.with_extension ~name:"x-domain" ~value:(`String "nodes")
  in
  let member name schema = Yojson.Safe.Util.member name (Json_schema.to_yojson schema) in
  List.iter [ "$defs"; "$id"; "$ref" ] ~f:(fun name ->
    assert (Yojson.Safe.equal (member name annotated) (member name original)))
;;

let%expect_test "invalid smart constructor input is rejected" =
  print_error (fun () -> Json_schema.string ~format:(`Custom " ") ());
  [%expect {| format must not be empty |}];
  print_error (fun () -> Json_schema.string ~min_length:(-1) ());
  [%expect {| minLength must be greater than or equal to zero |}];
  print_error (fun () -> Json_schema.string ~min_length:2 ~max_length:1 ());
  [%expect {| minLength must be less than or equal to maxLength |}];
  print_error (fun () -> Json_schema.string ~enum:[] ());
  [%expect {| enum must not be empty |}];
  print_error (fun () -> Json_schema.string ~enum:[ "a"; "a" ] ());
  [%expect {| enum contains duplicate value a |}];
  print_error (fun () -> Json_schema.string ~enum:[ "a" ] ~default:"b" ());
  [%expect {| default must be one of the enum values |}];
  print_error (fun () -> Json_schema.integer ~minimum:2 ~maximum:1 ());
  [%expect {| minimum must be less than or equal to maximum |}];
  print_error (fun () -> Json_schema.integer ~minimum:1 ~default:0 ());
  [%expect {| default must be within the declared range |}];
  print_error (fun () -> Json_schema.number ~minimum:Float.nan ());
  [%expect {| minimum must be finite |}];
  print_error (fun () ->
    Json_schema.array ~min_items:2 ~max_items:1 ~items:Json_schema.any ());
  [%expect {| minItems must be less than or equal to maxItems |}]
;;

let%test_unit "smart and PPX schemas satisfy the Draft 2020-12 meta-schema" =
  let schemas =
    [ Json_schema.to_yojson (Json_schema.string ~format:`Date_time ())
    ; Json_schema.to_yojson (Json_schema.integer ~format:`Int64 ~minimum:1 ())
    ; Json_schema.to_yojson (Json_schema.number ~minimum:0. ~maximum:1. ())
    ; Json_schema.to_yojson (Json_schema.boolean ~default:true ())
    ; Json_schema.to_yojson (Json_schema.array ~items:(Json_schema.string ()) ())
    ; Json_schema.to_yojson (Json_schema.dictionary ~values:(Json_schema.integer ()))
    ; Json_schema.to_yojson (Json_schema.nullable (Json_schema.string ()))
    ; Json_schema.to_yojson Ppx_bounded_integer.t_jsonschema
    ; Json_schema.to_yojson Ppx_formatted_string.t_jsonschema
    ]
  in
  List.iteri schemas ~f:(fun index schema ->
    let schema = Yojson.Safe.to_basic schema in
    match Jsonschema.validate Jsonschema.draft2020_12_validator schema with
    | Ok () -> ()
    | Error error ->
      Stdlib.failwith
        (Int.to_string index ^ ": " ^ Jsonschema.Validation_error.to_string error))
;;

let%test "a shared default makes an option alias optional in decoder and schema" =
  let decoder = Ppx_option_alias.optional_alias_of_yojson (`Assoc []) in
  let schema = Json_schema.to_yojson Ppx_option_alias.optional_alias_jsonschema in
  match decoder, Yojson.Safe.Util.member "required" schema with
  | Ok { value = None }, `List [] -> true
  | _ -> false
;;

module Generic_recursive = struct
  type 'a tree =
    { value : 'a
    ; children : 'a tree list
    }
  [@@deriving yojson, jsonschema]
end

module Mutual_recursive = struct
  type a = { next : b option }
  and b = { previous : a option } [@@deriving yojson, jsonschema]
end

let%test_unit "recursive generic and mutual schemas validate their wire values" =
  let validate schema value =
    let validator =
      Jsonschema.create_validator_from_json
        ~schema:(Yojson.Safe.to_basic (Json_schema.to_yojson schema))
        ()
      |> Result.map_error ~f:(fun error ->
        Stdlib.Format.asprintf "%a" Jsonschema.pp_compile_error error)
      |> Result.ok_or_failwith
    in
    assert (Result.is_ok (Jsonschema.validate validator (Yojson.Safe.to_basic value)))
  in
  validate
    (Generic_recursive.tree_jsonschema (Json_schema.integer ()))
    (`Assoc
        [ "value", `Int 1
        ; "children", `List [ `Assoc [ "value", `Int 2; "children", `List [] ] ]
        ]);
  validate
    Mutual_recursive.a_jsonschema
    (`Assoc [ "next", `Assoc [ "previous", `Assoc [ "next", `Null ] ] ]);
  validate
    Ppx_cross_module_dependency.t_jsonschema
    (`Assoc
        [ ( "node"
          , `Assoc [ "value", `Int 1; "next", `Assoc [ "value", `Int 2; "next", `Null ] ]
          )
        ])
;;
