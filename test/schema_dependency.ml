open! Base

type node =
  { value : int
  ; next : node option
  }
[@@deriving jsonschema]
