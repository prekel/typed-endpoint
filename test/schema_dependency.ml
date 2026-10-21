open! Base

type node =
  { value : int
  ; next : node option
  }
[@@deriving jsonschema { no_yojson = true }]
