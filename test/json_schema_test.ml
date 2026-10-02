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
  type t = string [@@jsonschema.format "date-time"] [@@deriving jsonschema]
end

module Ppx_wire_annotations = struct
  type t = { display_name : string option [@key "displayName"] [@default None] }
  [@@deriving yojson, jsonschema { strict = true }]
end

module Ppx_generic = struct
  type 'a t = { value : 'a } [@@deriving jsonschema]
end

module Ppx_permissive = struct
  type t = { value : int }
  [@@deriving yojson { strict = false }, jsonschema { strict = false }]
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

module Ppx_compact_variant = struct
  type t =
    | Empty
    | Value of int
  [@@deriving jsonschema] [@@jsonschema.compact_variants]
end

module Ppx_custom_default = struct
  type amount = int64 [@@deriving yojson]

  let amount_jsonschema = Json_schema.int64_exn ()

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

  type optional_alias = { value : maybe_string [@jsonschema.option] }
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
  print_if_equal (Json_schema.string_exn ()) Ppx_string.t_jsonschema;
  [%expect {| { "type": "string" } |}];
  print_if_equal (Json_schema.integer_exn ()) Ppx_integer.t_jsonschema;
  [%expect {| { "type": "integer" } |}];
  print_if_equal (Json_schema.number_exn ()) Ppx_number.t_jsonschema;
  [%expect {| { "type": "number" } |}];
  print_if_equal (Json_schema.boolean ()) Ppx_boolean.t_jsonschema;
  [%expect {| { "type": "boolean" } |}]
;;

let%expect_test "composed smart constructors agree with PPX schemas" =
  print_if_equal
    (Json_schema.array_exn ~items:(Json_schema.string_exn ()) ())
    Ppx_array.t_jsonschema;
  [%expect {| { "type": "array", "items": { "type": "string" } } |}];
  print_if_equal
    (Json_schema.nullable (Json_schema.string_exn ()))
    Ppx_nullable.t_jsonschema;
  [%expect {| { "type": [ "string", "null" ] } |}];
  print_if_equal
    (Json_schema.integer_exn ~minimum:1 ~maximum:100 ())
    Ppx_bounded_integer.t_jsonschema;
  [%expect {| { "type": "integer", "minimum": 1, "maximum": 100 } |}];
  print_if_equal
    (Json_schema.string_exn ~format:`Date_time ())
    Ppx_formatted_string.t_jsonschema;
  [%expect {| { "type": "string", "format": "date-time" } |}]
;;

let%expect_test "smart schemas have stable JSON output" =
  Json_schema.string_exn
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
  Json_schema.integer_exn ~format:`Int64 ~minimum:1 ~maximum:100 ~default:1 ()
  |> print_schema;
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
  Json_schema.array_exn ~min_items:1 ~max_items:3 ~items:(Json_schema.string_exn ()) ()
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
  Json_schema.dictionary ~values:(Json_schema.integer_exn ~format:`Int32 ())
  |> print_schema;
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
  Ppx_generic.t_jsonschema (Json_schema.integer_exn ()) |> print_schema;
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

let%expect_test "strict false permits extra object properties" =
  Ppx_permissive.t_jsonschema |> print_schema;
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

let%test "strict false schema mode matches the Yojson codec" =
  match Ppx_permissive.of_yojson (`Assoc [ "value", `Int 1; "extra", `Bool true ]) with
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

let%expect_test "allow_extra_fields remains accepted and is a no-op" =
  Ppx_allow_extra_fields.t_jsonschema |> print_schema;
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

let%expect_test "compact variants keep payload schemas" =
  Ppx_compact_variant.t_jsonschema |> print_schema;
  [%expect
    {|
    {
      "anyOf": [
        { "const": "Empty" },
        {
          "type": "array",
          "prefixItems": [ { "const": "Value" }, { "type": "integer" } ],
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
      "additionalProperties": true
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
      "additionalProperties": true
    }
    |}];
  Ppx_option_alias.optional_alias_jsonschema |> print_schema;
  [%expect
    {|
    {
      "type": "object",
      "properties": { "value": { "type": [ "string", "null" ] } },
      "required": [],
      "additionalProperties": true
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

let%test_unit "legacy ppx schema bridge preserves JSON structure" =
  let imported : string Json_schema.t =
    Json_schema.Unsafe.of_ppx (`Assoc [ "type", `String "string" ])
  in
  assert (Json_schema.equal imported (Json_schema.string_exn ()))
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
  let nullable = Json_schema.nullable (Json_schema.string_exn ()) in
  Json_schema.equal nullable (Json_schema.nullable nullable)
;;

let print_error = function
  | Ok _ -> Stdlib.print_endline "ok"
  | Error error -> Stdlib.print_endline error
;;

let%expect_test "invalid smart constructor input is rejected" =
  Json_schema.string ~format:(`Custom " ") () |> print_error;
  [%expect {| format must not be empty |}];
  Json_schema.string ~min_length:(-1) () |> print_error;
  [%expect {| minLength must be greater than or equal to zero |}];
  Json_schema.string ~min_length:2 ~max_length:1 () |> print_error;
  [%expect {| minLength must be less than or equal to maxLength |}];
  Json_schema.string ~enum:[] () |> print_error;
  [%expect {| enum must not be empty |}];
  Json_schema.string ~enum:[ "a"; "a" ] () |> print_error;
  [%expect {| enum contains duplicate value a |}];
  Json_schema.string ~enum:[ "a" ] ~default:"b" () |> print_error;
  [%expect {| default must be one of the enum values |}];
  Json_schema.integer ~minimum:2 ~maximum:1 () |> print_error;
  [%expect {| minimum must be less than or equal to maximum |}];
  Json_schema.integer ~minimum:1 ~default:0 () |> print_error;
  [%expect {| default must be within the declared range |}];
  Json_schema.number ~minimum:Float.nan () |> print_error;
  [%expect {| minimum must be finite |}];
  Json_schema.array ~min_items:2 ~max_items:1 ~items:Json_schema.any () |> print_error;
  [%expect {| minItems must be less than or equal to maxItems |}]
;;

let%test_unit "smart and PPX schemas satisfy the Draft 2020-12 meta-schema" =
  let schemas =
    [ Json_schema.to_yojson (Json_schema.string_exn ~format:`Date_time ())
    ; Json_schema.to_yojson (Json_schema.integer_exn ~format:`Int64 ~minimum:1 ())
    ; Json_schema.to_yojson (Json_schema.number_exn ~minimum:0. ~maximum:1. ())
    ; Json_schema.to_yojson (Json_schema.boolean ~default:true ())
    ; Json_schema.to_yojson (Json_schema.array_exn ~items:(Json_schema.string_exn ()) ())
    ; Json_schema.to_yojson (Json_schema.dictionary ~values:(Json_schema.integer_exn ()))
    ; Json_schema.to_yojson (Json_schema.nullable (Json_schema.string_exn ()))
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
