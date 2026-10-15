open! Base
open Typed_endpoint

let member json name = Yojson.Safe.Util.member name json

let property schema name =
  member (member (Json_schema.to_yojson schema) "properties") name
;;

let print json = Stdlib.print_endline (Yojson.Safe.to_string json)

(* Parse the actual JSON wire: Safe.to_basic turns Intlit into strings. *)
let basic json = Yojson.Basic.from_string (Yojson.Safe.to_string json)

let validator schema =
  match
    Jsonschema.create_validator_from_json
      ~schema:(basic (Json_schema.to_yojson schema))
      ()
  with
  | Ok validator -> validator
  | Error error ->
    Stdlib.failwith (Stdlib.Format.asprintf "%a" Jsonschema.pp_compile_error error)
;;

let check_wire schema encode decode value =
  let json = encode value in
  assert (Result.is_ok (Jsonschema.validate (validator schema) (basic json)));
  match decode json with
  | Ok decoded -> assert (Poly.equal value decoded)
  | Error error -> Stdlib.failwith error
;;

module Short = struct
  type t = { value : int [@key "wire"] [@default 7] } [@@deriving yojson, jsonschema]
end

module Prefixed = struct
  type t = { value : int [@yojson.key "wire"] [@yojson.default 7] }
  [@@deriving yojson, jsonschema]
end

module Qualified = struct
  type t = { value : int [@deriving.yojson.key "wire"] [@deriving.yojson.default 7] }
  [@@deriving yojson, jsonschema]
end

let%expect_test "all Yojson annotation namespaces describe the same record" =
  print (Json_schema.to_yojson Short.t_jsonschema);
  [%expect
    {| {"type":"object","properties":{"wire":{"default":7,"type":"integer"}},"required":[],"additionalProperties":false} |}];
  print (Json_schema.to_yojson Prefixed.t_jsonschema);
  [%expect
    {| {"type":"object","properties":{"wire":{"default":7,"type":"integer"}},"required":[],"additionalProperties":false} |}];
  print (Json_schema.to_yojson Qualified.t_jsonschema);
  [%expect
    {| {"type":"object","properties":{"wire":{"default":7,"type":"integer"}},"required":[],"additionalProperties":false} |}];
  check_wire Short.t_jsonschema Short.to_yojson Short.of_yojson { value = 8 };
  check_wire Prefixed.t_jsonschema Prefixed.to_yojson Prefixed.of_yojson { value = 8 };
  check_wire Qualified.t_jsonschema Qualified.to_yojson Qualified.of_yojson { value = 8 }
;;

module Priority = struct
  type t =
    { value : int
          [@key "short"]
          [@yojson.key "prefixed"]
          [@deriving.yojson.key "qualified"]
          [@default 1]
          [@yojson.default 2]
          [@deriving.yojson.default 3]
    }
  [@@deriving yojson, jsonschema]
end

let%expect_test "more qualified annotation names have Yojson's priority" =
  print (Json_schema.to_yojson Priority.t_jsonschema);
  [%expect
    {| {"type":"object","properties":{"qualified":{"default":3,"type":"integer"}},"required":[],"additionalProperties":false} |}];
  check_wire Priority.t_jsonschema Priority.to_yojson Priority.of_yojson { value = 4 };
  assert (Poly.equal (Priority.of_yojson (`Assoc [])) (Ok { Priority.value = 3 }))
;;

module Variants = struct
  type t =
    | Empty [@yojson.name "empty"]
    | Value of { value : int [@yojson.key "wire"] [@yojson.default 0] }
    [@deriving.yojson.name "value"]
  [@@deriving yojson, jsonschema]
end

module Poly_variants = struct
  type t =
    [ `Empty [@yojson.name "empty"]
    | `Value of int [@name "short"] [@deriving.yojson.name "value"]
    ]
  [@@deriving yojson, jsonschema]
end

let%expect_test "renamed variants and inline record fields match their codecs" =
  print (Variants.to_yojson (Value { value = 1 }));
  [%expect {| ["value",{"wire":1}] |}];
  check_wire
    Variants.t_jsonschema
    Variants.to_yojson
    Variants.of_yojson
    (Value { value = 1 });
  check_wire
    Variants.t_jsonschema
    Variants.to_yojson
    Variants.of_yojson
    (Value { value = 0 });
  check_wire Variants.t_jsonschema Variants.to_yojson Variants.of_yojson Empty;
  print (Poly_variants.to_yojson (`Value 1));
  [%expect {| ["value",1] |}];
  check_wire
    Poly_variants.t_jsonschema
    Poly_variants.to_yojson
    Poly_variants.of_yojson
    (`Value 1);
  check_wire
    Poly_variants.t_jsonschema
    Poly_variants.to_yojson
    Poly_variants.of_yojson
    `Empty
;;

module Variant_arguments = struct
  type pair = int * string [@@deriving yojson, jsonschema]

  type t =
    | Empty
    | Arguments of int * string
    | Tuple of (int * string)
    | Alias of pair
  [@@deriving yojson, jsonschema]

  type poly =
    [ `Empty
    | `Arguments of int * string
    | `Alias of pair
    ]
  [@@deriving yojson, jsonschema]
end

let%expect_test "variant arguments always use Yojson's tuple layout" =
  let open Variant_arguments in
  print (to_yojson Empty);
  [%expect {| ["Empty"] |}];
  print (to_yojson (Arguments (1, "x")));
  [%expect {| ["Arguments",1,"x"] |}];
  print (to_yojson (Tuple (1, "x")));
  [%expect {| ["Tuple",[1,"x"]] |}];
  print (poly_to_yojson (`Arguments (1, "x")));
  [%expect {| ["Arguments",1,"x"] |}];
  print (poly_to_yojson (`Alias (1, "x")));
  [%expect {| ["Alias",[1,"x"]] |}];
  List.iter
    [ Empty; Arguments (1, "x"); Tuple (1, "x"); Alias (1, "x") ]
    ~f:(check_wire t_jsonschema to_yojson of_yojson);
  List.iter
    [ `Empty; `Arguments (1, "x"); `Alias (1, "x") ]
    ~f:(check_wire poly_jsonschema poly_to_yojson poly_of_yojson)
;;

module Matching_strict = struct
  type t = { value : int }
  [@@deriving yojson, jsonschema { strict = true }] [@@jsonschema.disallow_extra_fields]
end

module Matching_permissive = struct
  type t = { value : int }
  [@@deriving yojson { strict = false }, jsonschema { strict = false }]
  [@@jsonschema.allow_extra_fields]
end

module Matching_inline = struct
  type t = Value of { value : int } [@jsonschema.allow_extra_fields]
  [@@deriving yojson { strict = false }, jsonschema]
end

module Standalone_inline = struct
  type t =
    | Open of { value : int } [@jsonschema.allow_extra_fields]
    | Closed of { value : int }
  [@@deriving jsonschema { strict = true }]
end

let%test_unit "explicit matching policies agree with Yojson decoders" =
  check_wire
    Matching_strict.t_jsonschema
    Matching_strict.to_yojson
    Matching_strict.of_yojson
    { value = 1 };
  check_wire
    Matching_permissive.t_jsonschema
    Matching_permissive.to_yojson
    Matching_permissive.of_yojson
    { value = 1 };
  check_wire
    Matching_inline.t_jsonschema
    Matching_inline.to_yojson
    Matching_inline.of_yojson
    (Value { value = 1 });
  let extra = `Assoc [ "value", `Int 1; "extra", `Bool true ] in
  assert (Result.is_error (Matching_strict.of_yojson extra));
  assert (
    Result.is_error
      (Jsonschema.validate (validator Matching_strict.t_jsonschema) (basic extra)));
  assert (Result.is_ok (Matching_permissive.of_yojson extra));
  assert (
    Result.is_ok
      (Jsonschema.validate (validator Matching_permissive.t_jsonschema) (basic extra)))
;;

let%test_unit "standalone inline policies override the default" =
  let branches =
    Json_schema.to_yojson Standalone_inline.t_jsonschema |> fun schema ->
    member schema "anyOf" |> Yojson.Safe.Util.to_list
  in
  let policies =
    List.map branches ~f:(fun branch ->
      let items = member branch "prefixItems" |> Yojson.Safe.Util.to_list in
      member (List.nth_exn items 1) "additionalProperties")
  in
  assert (Poly.equal policies [ `Bool true; `Bool false ])
;;

module Defaults = struct
  type t =
    { field : (int[@deriving.yojson.default 1]) [@default 2]
    ; core : (int[@yojson.default 3])
    ; nullable : string option
    ; optional : string option [@deriving.yojson.default None]
    }
  [@@deriving yojson, jsonschema]
end

let%expect_test "field defaults override core type defaults and determine required fields"
  =
  print (member (Json_schema.to_yojson Defaults.t_jsonschema) "required");
  [%expect {| ["nullable"] |}];
  print (member (property Defaults.t_jsonschema "field") "default");
  [%expect {| 2 |}];
  print (member (property Defaults.t_jsonschema "core") "default");
  [%expect {| 3 |}];
  let defaults = { Defaults.field = 2; core = 3; nullable = None; optional = None } in
  print (Defaults.to_yojson defaults);
  [%expect {| {"nullable":null} |}];
  assert (Poly.equal (Defaults.of_yojson (`Assoc [ "nullable", `Null ])) (Ok defaults));
  assert (Result.is_error (Defaults.of_yojson (`Assoc [])));
  assert (
    Result.is_error (Jsonschema.validate (validator Defaults.t_jsonschema) (`Assoc [])));
  check_wire Defaults.t_jsonschema Defaults.to_yojson Defaults.of_yojson defaults
;;

module Encodings = struct
  type t =
    { wide : int64 [@encoding `string] [@default 9223372036854775807L]
    ; native : (Nativeint.t[@yojson.encoding `string]) [@encoding `number] [@default 42n]
    ; number : (Int64.t[@deriving.yojson.encoding `number]) [@default 9L]
    ; plain : nativeint [@default 10n]
    }
  [@@deriving yojson, jsonschema]
end

let%expect_test "integer encoding controls the schema and defaults" =
  print (property Encodings.t_jsonschema "wide");
  [%expect {| {"default":"9223372036854775807","type":"string"} |}];
  print (property Encodings.t_jsonschema "native");
  [%expect {| {"default":"42","type":"string"} |}];
  print (property Encodings.t_jsonschema "number");
  [%expect {| {"default":9,"type":"integer"} |}];
  print (property Encodings.t_jsonschema "plain");
  [%expect {| {"default":10,"type":"integer"} |}];
  let value = { Encodings.wide = 1L; native = 2n; number = 3L; plain = 4n } in
  print (Encodings.to_yojson value);
  [%expect {| {"wide":"1","native":"2","number":3,"plain":4} |}];
  check_wire Encodings.t_jsonschema Encodings.to_yojson Encodings.of_yojson value
;;

module Nested = struct
  type t =
    { optional : (int64[@encoding `string]) option [@default Some 1L]
    ; list : (nativeint[@yojson.encoding `string]) list [@default [ 2n ]]
    ; array : (Int64.t[@deriving.yojson.encoding `string]) array [@default [| 3L |]]
    ; tuple : (int64[@encoding `string]) * (Nativeint.t[@encoding `number])
          [@default 4L, 5n]
    }
  [@@deriving yojson, jsonschema]
end

let%expect_test "nested integer encodings also serialize defaults through the codec" =
  print (property Nested.t_jsonschema "optional");
  [%expect {| {"default":"1","type":["string","null"]} |}];
  print (member (property Nested.t_jsonschema "list") "default");
  [%expect {| ["2"] |}];
  print (member (property Nested.t_jsonschema "array") "default");
  [%expect {| ["3"] |}];
  print (member (property Nested.t_jsonschema "tuple") "default");
  [%expect {| ["4",5] |}];
  assert (
    Poly.equal
      (member (property Nested.t_jsonschema "optional") "default")
      ([%to_yojson: (int64[@encoding `string]) option] (Some 1L)));
  assert (
    Poly.equal
      (member (property Nested.t_jsonschema "list") "default")
      ([%to_yojson: (nativeint[@encoding `string]) list] [ 2n ]));
  assert (
    Poly.equal
      (member (property Nested.t_jsonschema "array") "default")
      ([%to_yojson: (Int64.t[@encoding `string]) array] [| 3L |]));
  assert (
    Poly.equal
      (member (property Nested.t_jsonschema "tuple") "default")
      ([%to_yojson: (int64[@encoding `string]) * (Nativeint.t[@encoding `number])]
         (4L, 5n)));
  check_wire
    Nested.t_jsonschema
    Nested.to_yojson
    Nested.of_yojson
    { optional = Some 6L; list = [ 7n ]; array = [| 8L |]; tuple = 9L, 10n };
  let defaults =
    { Nested.optional = Some 1L; list = [ 2n ]; array = [| 3L |]; tuple = 4L, 5n }
  in
  assert (Poly.equal (Nested.of_yojson (`Assoc [])) (Ok defaults));
  check_wire Nested.t_jsonschema Nested.to_yojson Nested.of_yojson defaults
;;

module Encoded_alias = struct
  type t = (Int64.t[@encoding `string]) [@@deriving yojson, jsonschema]
end

module Alias_default = struct
  type t = { value : Encoded_alias.t [@default 42L] } [@@deriving yojson, jsonschema]
end

let%expect_test "named encoded types use their serializer for defaults" =
  print (property Alias_default.t_jsonschema "value");
  [%expect {| {"default":"42","type":"string"} |}];
  check_wire
    Alias_default.t_jsonschema
    Alias_default.to_yojson
    Alias_default.of_yojson
    { value = 43L }
;;
