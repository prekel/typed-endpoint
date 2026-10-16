open! Base
open Typed_endpoint

module Numeric = struct
  type t = { value : int64 } [@@deriving to_yojson, jsonschema]
end

module Textual = struct
  type t = { value : int64 [@encoding `string] } [@@deriving to_yojson, jsonschema]
end

module Native = struct
  type t = { value : int } [@@deriving to_yojson, jsonschema]
end

let () =
  let values =
    [ 9007199254740991L; 9007199254740992L; 9007199254740993L; 9223372036854775807L ]
  in
  let fixtures =
    List.map values ~f:(fun value ->
      `Assoc
        [ "decimal", `String (Int64.to_string value)
        ; "numeric", Numeric.to_yojson { value }
        ; "textual", Textual.to_yojson { value }
        ])
  in
  let native =
    `Assoc
      [ "decimal", `String (Int.to_string Int.max_value)
      ; "numeric", Native.to_yojson { value = Int.max_value }
      ]
  in
  `Assoc
    [ "fixtures", `List fixtures
    ; "native", native
    ; "numeric_schema", Json_schema.to_yojson Numeric.t_jsonschema
    ; "textual_schema", Json_schema.to_yojson Textual.t_jsonschema
    ; "native_schema", Json_schema.to_yojson Native.t_jsonschema
    ]
  |> Yojson.Safe.to_string
  |> Stdlib.print_endline
;;
