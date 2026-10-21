open! Base
open Typed_endpoint
module S = Json_schema

module Enum = struct
  type t =
    | A
    | B
  [@@deriving yojson, jsonschema]
end

module Payload = struct
  type t =
    | Empty [@name "empty"]
    | Value of int
    | Pair of string * bool
    | Row of
        { name : string
        ; count : int
        }
  [@@deriving yojson, jsonschema]
end

module Poly = struct
  type base =
    [ `A
    | `Value of int
    ]
  [@@deriving yojson, jsonschema]

  type t =
    [ base
    | `Pair of string * bool
    ]
  [@@deriving yojson, jsonschema]
end

module Tuple = struct
  type t = int * string [@@deriving yojson, jsonschema]
end

module Result_payload = struct
  type ('a, 'b) result = ('a, 'b) Result.t =
    | Ok of 'a
    | Error of 'b
  [@@deriving yojson]

  type t = (int, string) result [@@deriving yojson, jsonschema]
end

module Fields = struct
  type t =
    { count : int
    ; nullable : string option
    ; optional : string option [@default None]
    ; renamed : string [@key "wire"]
    ; wide : int64 [@encoding `string]
    ; values : bool array
    }
  [@@deriving yojson, jsonschema]
end

module Primitives = struct
  type t =
    { small : int32
    ; wide : int64
    ; number : float
    ; letter : char
    ; data : bytes
    ; empty : unit
    }
  [@@deriving yojson, jsonschema]
end

module Recursive = struct
  type t =
    { value : int
    ; next : t option
    }
  [@@deriving yojson, jsonschema]
end

module String_recursive = struct
  type t =
    { value : string
    ; next : t option
    }
  [@@deriving yojson, jsonschema]
end

module Nested = struct
  type t =
    { left : Recursive.t
    ; right : String_recursive.t
    }
  [@@deriving yojson, jsonschema]
end

module Mutual = struct
  type a = { next : b option }
  and b = { previous : a option } [@@deriving yojson, jsonschema]

  type t = a [@@deriving yojson, jsonschema]
end

module Generic = struct
  type 'a box = { value : 'a } [@@deriving yojson, jsonschema]
  type t = int box [@@deriving yojson, jsonschema]
end

module Open_record = struct
  type t = { value : int } [@@deriving yojson { strict = false }, jsonschema]
end

let fixture name schema ~accept ~reject =
  let exported = S.to_yojson_for_typescript schema |> Result.ok_or_failwith in
  `Assoc
    [ "name", `String name
    ; "original", S.to_yojson schema
    ; "exported", exported
    ; "accept", `List accept
    ; "reject", `List reject
    ]
;;

let wire name schema encode decode values ~reject =
  let accept = List.map values ~f:encode in
  List.iter accept ~f:(fun value -> assert (Result.is_ok (decode value)));
  fixture name schema ~accept ~reject
;;

let () =
  let int value = `Int value in
  let str value = `String value in
  let list values = `List values in
  let obj values = `Assoc values in
  let literal = obj [ "kind", str "fixed"; "count", int 2 ] in
  let boolean_refs =
    S.object_
      ~properties:
        [ ( "anything"
          , S.pack (S.Deriver.root_ref ~root:"Any" ~definitions:[ "Any", S.pack S.any ]) )
        ; ( "nothing"
          , S.pack
              (S.Deriver.root_ref ~root:"Never" ~definitions:[ "Never", S.pack S.never ])
          )
        ]
      ~required:[ "anything" ]
      ~additional_properties:Deny
      ()
  in
  [ wire
      "Nullary"
      Enum.t_jsonschema
      Enum.to_yojson
      Enum.of_yojson
      [ A; B ]
      ~reject:[ str "A"; list [ str "C" ]; list [ str "A"; int 1 ] ]
  ; wire
      "Payload"
      Payload.t_jsonschema
      Payload.to_yojson
      Payload.of_yojson
      [ Empty; Value 3; Pair ("x", true); Row { name = "r"; count = 2 } ]
      ~reject:[ list [ str "Value"; str "wrong" ]; list [ str "empty"; int 1 ] ]
  ; wire
      "Poly"
      Poly.t_jsonschema
      Poly.to_yojson
      Poly.of_yojson
      [ `A; `Value 2; `Pair ("x", false) ]
      ~reject:[ list [ str "Value"; str "wrong" ]; list [ str "Missing" ] ]
  ; wire
      "Tuple"
      Tuple.t_jsonschema
      Tuple.to_yojson
      Tuple.of_yojson
      [ 1, "x" ]
      ~reject:[ list [ int 1 ]; list [ str "x"; int 1 ]; list [ int 1; str "x"; int 2 ] ]
  ; wire
      "Result"
      Result_payload.t_jsonschema
      Result_payload.to_yojson
      Result_payload.of_yojson
      [ Ok 1; Error "failure" ]
      ~reject:[ list [ str "Ok"; str "wrong" ]; list [ str "Error"; int 2 ] ]
  ; wire
      "Fields"
      Fields.t_jsonschema
      Fields.to_yojson
      Fields.of_yojson
      [ { count = 1
        ; nullable = None
        ; optional = None
        ; renamed = "x"
        ; wide = 42L
        ; values = [| true |]
        }
      ; { count = 2
        ; nullable = Some "x"
        ; optional = Some "y"
        ; renamed = "z"
        ; wide = 43L
        ; values = [||]
        }
      ]
      ~reject:[ obj []; obj [ "count", str "wrong" ] ]
  ; wire
      "Recursive"
      Recursive.t_jsonschema
      Recursive.to_yojson
      Recursive.of_yojson
      [ { value = 1; next = Some { value = 2; next = None } } ]
      ~reject:[ obj [ "value", str "wrong"; "next", `Null ] ]
  ; wire
      "Primitives"
      Primitives.t_jsonschema
      Primitives.to_yojson
      Primitives.of_yojson
      [ { small = 1l
        ; wide = 2L
        ; number = 1.5
        ; letter = 'a'
        ; data = Bytes.of_string "x"
        ; empty = ()
        }
      ]
      ~reject:[ obj [] ]
  ; wire
      "Nested"
      Nested.t_jsonschema
      Nested.to_yojson
      Nested.of_yojson
      [ { left = { value = 1; next = None }
        ; right = { value = "x"; next = Some { value = "y"; next = None } }
        }
      ]
      ~reject:
        [ obj
            [ "left", obj [ "value", str "wrong"; "next", `Null ]
            ; "right", obj [ "value", str "x"; "next", `Null ]
            ]
        ]
  ; wire
      "Mutual"
      Mutual.t_jsonschema
      Mutual.to_yojson
      Mutual.of_yojson
      [ { next = Some { previous = Some { next = None } } } ]
      ~reject:[ obj [ "next", int 1 ] ]
  ; wire
      "Generic"
      Generic.t_jsonschema
      Generic.to_yojson
      Generic.of_yojson
      [ { value = 1 } ]
      ~reject:[ obj [] ]
  ; wire
      "OpenRecord"
      Open_record.t_jsonschema
      Open_record.to_yojson
      Open_record.of_yojson
      [ { value = 1 } ]
      ~reject:[ obj [ "value", str "wrong" ] ]
  ; fixture
      "Dictionary"
      (S.dictionary ~values:(S.integer ()))
      ~accept:[ obj [ "a", int 1; "b", int 2 ]; obj [] ]
      ~reject:[ obj [ "a", str "wrong" ] ]
  ; fixture
      "Collection"
      (S.list ~items:(S.string ()) ())
      ~accept:[ list []; list [ str "a"; str "b" ] ]
      ~reject:[ list [ int 1 ] ]
  ; fixture
      "Union"
      (S.one_of [ S.as_json (S.integer ()); S.as_json (S.string ()) ])
      ~accept:[ int 1; str "x" ]
      ~reject:[ `Null; obj [] ]
  ; fixture
      "Intersection"
      (S.all_of [ S.string ~min_length:1 (); S.string ~max_length:3 () ])
      ~accept:[ str "x"; str "abc" ]
      ~reject:[ str ""; str "abcd"; int 1 ]
  ; fixture
      "RootRecursive"
      (S.Unsafe.of_yojson
         (Yojson.Safe.from_string
            {|{"type":"object","properties":{"next":{"anyOf":[{"type":"null"},{"$ref":"#"}]}},"required":["next"],"additionalProperties":false}|}))
      ~accept:[ obj [ "next", `Null ]; obj [ "next", obj [ "next", `Null ] ] ]
      ~reject:[ obj [ "next", int 1 ]; obj [] ]
  ; fixture
      "StringEnum"
      (S.string ~enum:[ "red"; "blue" ] ())
      ~accept:[ str "red"; str "blue" ]
      ~reject:[ str "green"; int 1 ]
  ; fixture
      "Literal"
      (S.with_const ~encode:Fn.id literal S.any)
      ~accept:[ literal ]
      ~reject:[ obj [ "kind", str "other"; "count", int 2 ] ]
  ; fixture
      "CompositeEnum"
      (S.with_enum ~encode:Fn.id [ list [ str "a" ]; list [ str "b" ] ] S.any)
      ~accept:[ list [ str "a" ]; list [ str "b" ] ]
      ~reject:[ list [ str "c" ] ]
  ; fixture
      "TypedTail"
      (S.list
         ~prefix_items:[ S.as_json (S.integer ()) ]
         ~items:(S.as_json (S.string ()))
         ~min_items:1
         ())
      ~accept:[ list [ int 1 ]; list [ int 1; str "x"; str "y" ] ]
      ~reject:[ list []; list [ int 1; int 2 ] ]
  ; fixture "Any" S.any ~accept:[ `Null; int 1; str "x"; obj []; list [] ] ~reject:[]
  ; fixture "Never" S.never ~accept:[] ~reject:[ `Null; int 1; obj []; list [] ]
  ; fixture
      "BooleanRefs"
      boolean_refs
      ~accept:[ obj [ "anything", int 1 ]; obj [ "anything", `Null ] ]
      ~reject:[ obj []; obj [ "anything", int 1; "nothing", int 1 ] ]
  ]
  |> (fun fixtures -> `List fixtures)
  |> Yojson.Safe.to_string
  |> Stdlib.print_endline
;;
