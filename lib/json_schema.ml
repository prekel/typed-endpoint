open! Base

type t = Ppx_deriving_jsonschema_runtime.t

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

let any : t = `Bool true
let null : t = `Assoc [ "type", `String "null" ]

let rec to_yojson : t -> Yojson.Safe.t = function
  | `Assoc fields ->
    `Assoc (List.map fields ~f:(fun (name, value) -> name, to_yojson value))
  | `List values -> `List (List.map values ~f:to_yojson)
  | (`Null | `Bool _ | `Int _ | `Float _ | `String _) as value -> value
;;

let of_ppx schema = schema
let to_ppx schema = schema

let rec normalize : Yojson.Safe.t -> Yojson.Safe.t = function
  | `Assoc fields ->
    `Assoc
      (fields
       |> List.map ~f:(fun (name, value) -> name, normalize value)
       |> List.sort ~compare:(fun (left, _) (right, _) -> String.compare left right))
  | `List values -> `List (List.map values ~f:normalize)
  | (`Null | `Bool _ | `Int _ | `Intlit _ | `Float _ | `String _) as value -> value
;;

let equal (left : t) (right : t) =
  Yojson.Safe.equal (normalize (to_yojson left)) (normalize (to_yojson right))
;;

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
   : t)
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
   : t)
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
   : t)
;;

let boolean ?default () : t =
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
   : t)
;;

let dictionary ~values : t =
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

let number_exn ?format ?minimum ?maximum ?default () =
  number ?format ?minimum ?maximum ?default () |> value_exn
;;

let array_exn ?min_items ?max_items ~items () =
  array ?min_items ?max_items ~items () |> value_exn
;;

module Unsafe = struct
  let rec of_yojson : Yojson.Safe.t -> t = function
    | `Assoc fields ->
      `Assoc (List.map fields ~f:(fun (name, value) -> name, of_yojson value))
    | `List values -> `List (List.map values ~f:of_yojson)
    | `Intlit value ->
      (match Int.of_string_opt value with
       | Some value -> `Int value
       | None -> Stdlib.invalid_arg "JSON Schema integer literal does not fit in int")
    | (`Null | `Bool _ | `Int _ | `Float _ | `String _) as value -> value
  ;;
end
