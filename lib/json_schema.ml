open! Base

type ppx_schema =
  [ `Null
  | `String of string
  | `Float of float
  | `Int of int
  | `Bool of bool
  | `List of ppx_schema list
  | `Assoc of (string * ppx_schema) list
  ]

type 'a t = Yojson.Safe.t
type packed = Pack : 'a t -> packed

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

type integer_format =
  [ `Int32
  | `Int64
  | `Custom of string
  ]

type number_format =
  [ `Double
  | `Float
  | `Custom of string
  ]

let any : Yojson.Safe.t t = `Bool true
let null : unit t = `Assoc [ "type", `String "null" ]
let to_yojson schema = schema
let pack schema = Pack schema
let to_yojson_packed (Pack schema) = schema

let rec of_ppx : ppx_schema -> 'a t = function
  | `Assoc fields -> `Assoc (List.map fields ~f:(fun (name, value) -> name, of_ppx value))
  | `List values -> `List (List.map values ~f:of_ppx)
  | (`Null | `Bool _ | `Int _ | `Float _ | `String _) as value -> value
;;

let rec to_ppx : 'a t -> ppx_schema = function
  | `Assoc fields -> `Assoc (List.map fields ~f:(fun (name, value) -> name, to_ppx value))
  | `List values -> `List (List.map values ~f:to_ppx)
  | `Intlit value ->
    (match Int.of_string_opt value with
     | Some value -> `Int value
     | None -> Stdlib.invalid_arg "JSON Schema integer literal does not fit in int")
  | (`Null | `Bool _ | `Int _ | `Float _ | `String _) as value -> value
  | _ -> Stdlib.invalid_arg "JSON Schema must contain only JSON values"
[@@warning "-11"]
;;

let rec normalize : Yojson.Safe.t -> Yojson.Safe.t = function
  | `Assoc fields ->
    `Assoc
      (fields
       |> List.map ~f:(fun (name, value) -> name, normalize value)
       |> List.sort ~compare:(fun (left, _) (right, _) -> String.compare left right))
  | `List values -> `List (List.map values ~f:normalize)
  | (`Null | `Bool _ | `Int _ | `Intlit _ | `Float _ | `String _) as value -> value
  | _ -> Stdlib.invalid_arg "JSON Schema must contain only JSON values"
[@@warning "-11"]
;;

let equal (left : 'a t) (right : 'b t) =
  Yojson.Safe.equal (normalize left) (normalize right)
;;

let equal_packed (Pack left) (Pack right) = equal left right
let field name map = Option.map ~f:(fun value -> name, map value)

let string_format_name : string_format -> string = function
  | `Binary -> "binary"
  | `Byte -> "byte"
  | `Date -> "date"
  | `Date_time -> "date-time"
  | `Duration -> "duration"
  | `Email -> "email"
  | `Hostname -> "hostname"
  | `Idn_email -> "idn-email"
  | `Idn_hostname -> "idn-hostname"
  | `Ipv4 -> "ipv4"
  | `Ipv6 -> "ipv6"
  | `Iri -> "iri"
  | `Iri_reference -> "iri-reference"
  | `Json_pointer -> "json-pointer"
  | `Password -> "password"
  | `Regex -> "regex"
  | `Relative_json_pointer -> "relative-json-pointer"
  | `Time -> "time"
  | `Uri -> "uri"
  | `Uri_reference -> "uri-reference"
  | `Uri_template -> "uri-template"
  | `Uuid -> "uuid"
  | `Custom name -> name
;;

let integer_format_name : integer_format -> string = function
  | `Int32 -> "int32"
  | `Int64 -> "int64"
  | `Custom name -> name
;;

let number_format_name : number_format -> string = function
  | `Double -> "double"
  | `Float -> "float"
  | `Custom name -> name
;;

let validate_format = function
  | Some format when String.is_empty (String.strip format) ->
    Error "format must not be empty"
  | _ -> Ok ()
;;

let validate_non_negative keyword = function
  | Some value when value < 0 -> Error (keyword ^ " must be greater than or equal to zero")
  | _ -> Ok ()
;;

let validate_range ~compare ~minimum_keyword ~maximum_keyword ~minimum ~maximum =
  match minimum, maximum with
  | Some minimum, Some maximum when compare minimum maximum > 0 ->
    Error (minimum_keyword ^ " must be less than or equal to " ^ maximum_keyword)
  | _ -> Ok ()
;;

let validate_float keyword = function
  | Some value when not (Float.is_finite value) -> Error (keyword ^ " must be finite")
  | _ -> Ok ()
;;

let validate_enum = function
  | Some [] -> Error "enum must not be empty"
  | Some values ->
    (match List.find_a_dup values ~compare:String.compare with
     | Some value -> Error ("enum contains duplicate value " ^ value)
     | None -> Ok ())
  | None -> Ok ()
;;

let validate_string_default ~enum ~default =
  match enum, default with
  | Some values, Some default when not (List.mem values default ~equal:String.equal) ->
    Error "default must be one of the enum values"
  | _ -> Ok ()
;;

let string ?format ?enum ?min_length ?max_length ?default () =
  let open Result.Let_syntax in
  let format = Option.map format ~f:string_format_name in
  let%bind () = validate_format format in
  let%bind () = validate_non_negative "minLength" min_length in
  let%bind () = validate_non_negative "maxLength" max_length in
  let%bind () =
    validate_range
      ~compare:Int.compare
      ~minimum_keyword:"minLength"
      ~maximum_keyword:"maxLength"
      ~minimum:min_length
      ~maximum:max_length
  in
  let%bind () = validate_enum enum in
  let%map () = validate_string_default ~enum ~default in
  (`Assoc
     (List.filter_opt
        [ Some ("type", `String "string")
        ; field "format" (fun value -> `String value) format
        ; field
            "enum"
            (fun values -> `List (List.map values ~f:(fun value -> `String value)))
            enum
        ; field "minLength" (fun value -> `Int value) min_length
        ; field "maxLength" (fun value -> `Int value) max_length
        ; field "default" (fun value -> `String value) default
        ])
   : string t)
;;

let validate_default_range ~compare ~minimum ~maximum = function
  | Some default
    when Option.exists minimum ~f:(fun minimum -> compare default minimum < 0)
         || Option.exists maximum ~f:(fun maximum -> compare default maximum > 0) ->
    Error "default must be within the declared range"
  | _ -> Ok ()
;;

let integer ?format ?minimum ?maximum ?default () =
  let open Result.Let_syntax in
  let format = Option.map format ~f:integer_format_name in
  let%bind () = validate_format format in
  let%bind () =
    validate_range
      ~compare:Int.compare
      ~minimum_keyword:"minimum"
      ~maximum_keyword:"maximum"
      ~minimum
      ~maximum
  in
  let%map () = validate_default_range ~compare:Int.compare ~minimum ~maximum default in
  (`Assoc
     (List.filter_opt
        [ Some ("type", `String "integer")
        ; field "format" (fun value -> `String value) format
        ; field "minimum" (fun value -> `Int value) minimum
        ; field "maximum" (fun value -> `Int value) maximum
        ; field "default" (fun value -> `Int value) default
        ])
   : int t)
;;

let int64 ?format ?minimum ?maximum ?default () =
  let open Result.Let_syntax in
  let format = Option.map format ~f:integer_format_name in
  let%bind () = validate_format format in
  let%bind () =
    validate_range
      ~compare:Int64.compare
      ~minimum_keyword:"minimum"
      ~maximum_keyword:"maximum"
      ~minimum
      ~maximum
  in
  let%map () = validate_default_range ~compare:Int64.compare ~minimum ~maximum default in
  (`Assoc
     (List.filter_opt
        [ Some ("type", `String "integer")
        ; field "format" (fun value -> `String value) format
        ; field "minimum" (fun value -> `Intlit (Int64.to_string value)) minimum
        ; field "maximum" (fun value -> `Intlit (Int64.to_string value)) maximum
        ; field "default" (fun value -> `Intlit (Int64.to_string value)) default
        ])
   : int64 t)
;;

let number ?format ?minimum ?maximum ?default () =
  let open Result.Let_syntax in
  let format = Option.map format ~f:number_format_name in
  let%bind () = validate_format format in
  let%bind () = validate_float "minimum" minimum in
  let%bind () = validate_float "maximum" maximum in
  let%bind () = validate_float "default" default in
  let%bind () =
    validate_range
      ~compare:Float.compare
      ~minimum_keyword:"minimum"
      ~maximum_keyword:"maximum"
      ~minimum
      ~maximum
  in
  let%map () = validate_default_range ~compare:Float.compare ~minimum ~maximum default in
  (`Assoc
     (List.filter_opt
        [ Some ("type", `String "number")
        ; field "format" (fun value -> `String value) format
        ; field "minimum" (fun value -> `Float value) minimum
        ; field "maximum" (fun value -> `Float value) maximum
        ; field "default" (fun value -> `Float value) default
        ])
   : float t)
;;

let boolean ?default () : bool t =
  `Assoc
    (List.filter_opt
       [ Some ("type", `String "boolean")
       ; field "default" (fun value -> `Bool value) default
       ])
;;

let array ?min_items ?max_items ~items () =
  let open Result.Let_syntax in
  let%bind () = validate_non_negative "minItems" min_items in
  let%bind () = validate_non_negative "maxItems" max_items in
  let%map () =
    validate_range
      ~compare:Int.compare
      ~minimum_keyword:"minItems"
      ~maximum_keyword:"maxItems"
      ~minimum:min_items
      ~maximum:max_items
  in
  (`Assoc
     (List.filter_opt
        [ Some ("type", `String "array")
        ; Some ("items", items)
        ; field "minItems" (fun value -> `Int value) min_items
        ; field "maxItems" (fun value -> `Int value) max_items
        ])
   : 'a array t)
;;

let list ?min_items ?max_items ~items () =
  let open Result.Let_syntax in
  let%map schema = array ?min_items ?max_items ~items () in
  (schema : 'a list t)
;;

let dictionary ~values : (string * 'a) list t =
  `Assoc [ "type", `String "object"; "additionalProperties", values ]
;;

let nullable schema =
  let already_nullable =
    match schema with
    | `Assoc fields ->
      (match List.Assoc.find fields "type" ~equal:String.equal with
       | Some (`String "null") -> true
       | Some (`List types) -> List.mem types (`String "null") ~equal:Poly.equal
       | _ ->
         (match List.Assoc.find fields "anyOf" ~equal:String.equal with
          | Some (`List schemas) -> List.mem schemas null ~equal:Poly.equal
          | _ -> false))
    | _ -> false
  in
  if already_nullable then
    schema
  else (
    match
      schema
    with
    | `Assoc fields ->
      (match List.Assoc.find fields "type" ~equal:String.equal with
       | Some (`String kind) ->
         `Assoc
           (List.map fields ~f:(fun (name, value) ->
              if String.equal name "type" then
                name, `List [ `String kind; `String "null" ]
              else
                name, value))
       | _ -> `Assoc [ "anyOf", `List [ schema; null ] ])
    | _ -> `Assoc [ "anyOf", `List [ schema; null ] ])
;;

module Deriver = struct
  type schema_type =
    | Array
    | Boolean
    | Integer
    | Null
    | Number
    | Object
    | String

  type additional_properties =
    | Allow
    | Deny
    | Schema of packed

  let type_name = function
    | Array -> "array"
    | Boolean -> "boolean"
    | Integer -> "integer"
    | Null -> "null"
    | Number -> "number"
    | Object -> "object"
    | String -> "string"
  ;;

  let packed_schema (Pack schema) = schema
  let type_schema schema_type : 'a t = `Assoc [ "type", `String (type_name schema_type) ]
  let const_string value : 'a t = `Assoc [ "const", `String value ]
  let type_ref name : 'a t = `Assoc [ "$ref", `String ("#/$defs/" ^ name) ]

  let array ~items : 'a t =
    `Assoc [ "type", `String "array"; "items", packed_schema items ]
  ;;

  let tuple items : 'a t =
    let items = List.map items ~f:packed_schema in
    let length = List.length items in
    `Assoc
      [ "type", `String "array"
      ; "prefixItems", `List items
      ; "unevaluatedItems", `Bool false
      ; "minItems", `Int length
      ; "maxItems", `Int length
      ]
  ;;

  let any_of schemas : 'a t =
    `Assoc [ "anyOf", `List (List.map schemas ~f:packed_schema) ]
  ;;

  let one_of schemas : 'a t =
    `Assoc [ "oneOf", `List (List.map schemas ~f:packed_schema) ]
  ;;

  let record ~properties ~required ~additional_properties : 'a t =
    let properties =
      List.map properties ~f:(fun (name, schema) -> name, packed_schema schema)
    in
    let additional_properties =
      match additional_properties with
      | Allow -> `Bool true
      | Deny -> `Bool false
      | Schema schema -> packed_schema schema
    in
    `Assoc
      [ "type", `String "object"
      ; "properties", `Assoc properties
      ; "required", `List (List.map required ~f:(fun name -> `String name))
      ; "additionalProperties", additional_properties
      ]
  ;;

  let merge_definitions first second =
    List.fold second ~init:first ~f:(fun definitions (name, schema) ->
      if List.exists definitions ~f:(fun (known, _) -> String.equal known name) then
        definitions
      else
        definitions @ [ name, schema ])
  ;;

  let root_ref ~root ~definitions : 'a t =
    let definitions = merge_definitions [] definitions in
    `Assoc
      [ ( "$defs"
        , `Assoc
            (List.map definitions ~f:(fun (name, schema) -> name, packed_schema schema)) )
      ; "$ref", `String ("#/$defs/" ^ root)
      ]
  ;;

  let definitions schema =
    match schema with
    | `Assoc fields ->
      (match List.Assoc.find fields "$defs" ~equal:String.equal with
       | Some (`Assoc definitions) ->
         List.map definitions ~f:(fun (name, schema) -> name, Pack schema)
       | _ -> [])
    | _ -> []
  ;;

  let without_definitions schema =
    match schema with
    | `Assoc fields ->
      (`Assoc (List.filter fields ~f:(fun (name, _) -> not (String.equal name "$defs")))
       : 'a t)
    | _ -> schema
  ;;

  let with_definitions extra schema =
    let definitions = merge_definitions (definitions schema) extra in
    if List.is_empty definitions then
      schema
    else (
      match
        without_definitions schema
      with
      | `Assoc fields ->
        (`Assoc
           (( "$defs"
            , `Assoc
                (List.map definitions ~f:(fun (name, schema) ->
                   name, packed_schema schema)) )
            :: fields)
         : 'a t)
      | _ -> schema)
  ;;

  let with_id id schema =
    if List.is_empty (definitions schema) then
      schema
    else (
      match
        schema
      with
      | `Assoc fields ->
        (`Assoc
           (("$id", `String id)
            :: List.filter fields ~f:(fun (name, _) -> not (String.equal name "$id")))
         : 'a t)
      | _ -> schema)
  ;;

  let with_annotation name value schema =
    match schema with
    | `Assoc fields ->
      (`Assoc
         ((name, value)
          :: List.filter fields ~f:(fun (field, _) -> not (String.equal field name)))
       : 'a t)
    | _ -> `Assoc [ name, value; "allOf", `List [ schema ] ]
  ;;

  let with_title title schema = with_annotation "title" (`String title) schema

  let with_description description schema =
    with_annotation "description" (`String description) schema
  ;;

  let with_format format schema = with_annotation "format" (`String format) schema
  let with_minimum_int value schema = with_annotation "minimum" (`Int value) schema
  let with_minimum_number value schema = with_annotation "minimum" (`Float value) schema
  let with_maximum_int value schema = with_annotation "maximum" (`Int value) schema
  let with_maximum_number value schema = with_annotation "maximum" (`Float value) schema

  let with_string_lengths ?minimum ?maximum schema =
    let fields =
      List.filter_map
        [ Option.map minimum ~f:(fun value -> "minLength", `Int value)
        ; Option.map maximum ~f:(fun value -> "maxLength", `Int value)
        ]
        ~f:Fn.id
    in
    List.fold_right fields ~init:schema ~f:(fun (name, value) schema ->
      with_annotation name value schema)
  ;;

  let with_default default schema = with_annotation "default" (normalize default) schema
end

let value_exn = function
  | Ok value -> value
  | Error error -> Stdlib.invalid_arg error
;;

let string_exn ?format ?enum ?min_length ?max_length ?default () =
  string ?format ?enum ?min_length ?max_length ?default () |> value_exn
;;

let integer_exn ?format ?minimum ?maximum ?default () =
  integer ?format ?minimum ?maximum ?default () |> value_exn
;;

let int64_exn ?format ?minimum ?maximum ?default () =
  int64 ?format ?minimum ?maximum ?default () |> value_exn
;;

let number_exn ?format ?minimum ?maximum ?default () =
  number ?format ?minimum ?maximum ?default () |> value_exn
;;

let array_exn ?min_items ?max_items ~items () =
  array ?min_items ?max_items ~items () |> value_exn
;;

let list_exn ?min_items ?max_items ~items () =
  list ?min_items ?max_items ~items () |> value_exn
;;

module Unsafe = struct
  let rec of_yojson : Yojson.Safe.t -> 'a t = function
    | `Assoc fields ->
      `Assoc (List.map fields ~f:(fun (name, value) -> name, of_yojson value))
    | `List values -> `List (List.map values ~f:of_yojson)
    | `Intlit value -> `Intlit value
    | (`Null | `Bool _ | `Int _ | `Float _ | `String _) as value -> value
    | _ -> Stdlib.invalid_arg "JSON Schema must contain only JSON values"
  [@@warning "-11"]
  ;;

  let of_ppx = of_ppx
end
