open! Base
open Typed_endpoint
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson

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
  [@@deriving yojson, jsonschema]
end

let print_schema schema =
  Json_schema.to_yojson schema |> Yojson.Safe.pretty_to_string |> Stdlib.print_endline
;;

let print_if_equal smart ppx =
  let ppx = Json_schema.of_ppx ppx in
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

let%expect_test "PPX wire annotations cross the explicit bridge unchanged" =
  Json_schema.of_ppx Ppx_wire_annotations.t_jsonschema |> print_schema;
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

let ordered_schema =
  Json_schema.Unsafe.of_yojson
    (`Assoc [ "type", `String "array"; "enum", `List [ `Int 1; `Int 2 ] ])
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
    [ Json_schema.string_exn ~format:`Date_time ()
    ; Json_schema.integer_exn ~format:`Int64 ~minimum:1 ()
    ; Json_schema.number_exn ~minimum:0. ~maximum:1. ()
    ; Json_schema.boolean ~default:true ()
    ; Json_schema.array_exn ~items:(Json_schema.string_exn ()) ()
    ; Json_schema.dictionary ~values:(Json_schema.integer_exn ())
    ; Json_schema.nullable (Json_schema.string_exn ())
    ; Json_schema.of_ppx Ppx_bounded_integer.t_jsonschema
    ; Json_schema.of_ppx Ppx_formatted_string.t_jsonschema
    ]
  in
  List.iteri schemas ~f:(fun index schema ->
    let schema = Json_schema.to_yojson schema |> Yojson.Safe.to_basic in
    match Jsonschema.validate Jsonschema.draft2020_12_validator schema with
    | Ok () -> ()
    | Error error ->
      Stdlib.failwith
        (Int.to_string index ^ ": " ^ Jsonschema.Validation_error.to_string error))
;;
