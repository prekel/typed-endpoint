open! Base

exception Invalid_schema of string

let () =
  Stdlib.Printexc.register_printer (function
    | Invalid_schema message ->
      Some ("Typed_endpoint.Json_schema.Invalid_schema: " ^ message)
    | _ -> None)
;;

type 'a t =
  { value : Yojson.Safe.t
  ; schema_name : string option
  ; description : string option
  ; tags : string list
  }

let create value = { value; schema_name = None; description = None; tags = [] }
let map_value schema ~f = { schema with value = f schema.value }

let with_openapi ?schema_name ?description ?tags schema =
  { schema with
    schema_name = Option.first_some schema_name schema.schema_name
  ; description = Option.first_some description schema.description
  ; tags = Option.value tags ~default:schema.tags
  }
;;

let schema_name schema = schema.schema_name
let tags schema = schema.tags

let description schema =
  match schema.description with
  | Some description -> description
  | None ->
    (match schema.value with
     | `Assoc fields ->
       (match List.Assoc.find fields "description" ~equal:String.equal with
        | Some (`String description) -> description
        | _ -> "")
     | _ -> "")
;;

type packed = Pack : 'a t -> packed

type additional_properties =
  | Allow
  | Deny
  | Schema of packed

let contramap (schema : 'a t) ~f:(_ : 'b -> 'a) : 'b t =
  { value = schema.value
  ; schema_name = schema.schema_name
  ; description = schema.description
  ; tags = schema.tags
  }
;;

let as_json schema : Yojson.Safe.t t =
  { value = schema.value
  ; schema_name = schema.schema_name
  ; description = schema.description
  ; tags = schema.tags
  }
;;

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

let any : Yojson.Safe.t t = create (`Bool true)
let never : Yojson.Safe.t t = create (`Bool false)
let null : unit t = create (`Assoc [ "type", `String "null" ])
let to_yojson schema = schema.value
let pack schema = Pack schema
let to_yojson_packed (Pack schema) = to_yojson schema

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
  Yojson.Safe.equal (normalize left.value) (normalize right.value)
;;

let equal_packed (Pack left) (Pack right) = equal left right
let field name map = Option.map ~f:(fun value -> name, map value)

let unwrap = function
  | Ok value -> value
  | Error error -> raise (Invalid_schema error)
;;

let member fields name = List.Assoc.find fields name ~equal:String.equal

let validate_unique_names keyword names =
  match List.find_a_dup names ~compare:String.compare with
  | None -> Ok ()
  | Some name -> Error (keyword ^ " contains duplicate name " ^ name)
;;

(* Only schema positions are traversed: literals and annotations may contain
   objects that look like schemas but must retain their original data. *)
let schema_maps = [ "properties"; "patternProperties"; "dependentSchemas" ]
let schema_lists = [ "allOf"; "anyOf"; "oneOf"; "prefixItems" ]

let schema_values =
  [ "items"
  ; "contains"
  ; "additionalProperties"
  ; "unevaluatedProperties"
  ; "unevaluatedItems"
  ; "propertyNames"
  ; "not"
  ; "if"
  ; "then"
  ; "else"
  ; "contentSchema"
  ]
;;

let prepare_schemas schemas =
  let open Result.Let_syntax in
  let add_definition definitions (name, value) =
    match member definitions name with
    | None -> Ok (definitions @ [ name, value ])
    | Some existing when Yojson.Safe.equal (normalize existing) (normalize value) ->
      Ok definitions
    | Some _ -> Error ("conflicting local definition " ^ name)
  in
  let rec visit definitions = function
    | `Assoc fields when Option.is_some (member fields "$id") ->
      Ok (definitions, `Assoc fields)
    | `Assoc fields ->
      let%bind definitions =
        match member fields "$defs" with
        | Some (`Assoc entries) ->
          let%bind () = validate_unique_names "$defs" (List.map entries ~f:fst) in
          List.fold_result entries ~init:definitions ~f:(fun definitions (name, value) ->
            let%bind definitions, value = visit definitions value in
            add_definition definitions (name, value))
        | None -> Ok definitions
        | Some _ -> Error "$defs must be an object"
      in
      let%map definitions, fields =
        List.fold_result
          fields
          ~init:(definitions, [])
          ~f:(fun (definitions, output) (name, value) ->
            if String.equal name "$defs" then
              Ok (definitions, output)
            else (
              let%map definitions, value =
                if List.mem schema_maps name ~equal:String.equal then
                  visit_map definitions value
                else if List.mem schema_lists name ~equal:String.equal then
                  visit_list definitions value
                else if List.mem schema_values name ~equal:String.equal then
                  visit definitions value
                else
                  Ok (definitions, value)
              in
              definitions, (name, value) :: output))
      in
      definitions, `Assoc (List.rev fields)
    | value -> Ok (definitions, value)
  and visit_map definitions = function
    | `Assoc fields ->
      let%map definitions, fields =
        List.fold_result
          fields
          ~init:(definitions, [])
          ~f:(fun (definitions, output) (name, value) ->
            let%map definitions, value = visit definitions value in
            definitions, (name, value) :: output)
      in
      definitions, `Assoc (List.rev fields)
    | value -> Ok (definitions, value)
  and visit_list definitions = function
    | `List values ->
      let%map definitions, values = visit_many definitions values in
      definitions, `List values
    | value -> Ok (definitions, value)
  and visit_many definitions values =
    let%map definitions, values =
      List.fold_result
        values
        ~init:(definitions, [])
        ~f:(fun (definitions, output) value ->
          let%map definitions, value = visit definitions value in
          definitions, value :: output)
    in
    definitions, List.rev values
  in
  visit_many [] schemas
;;

let attach_definitions definitions fields =
  `Assoc
    (if List.is_empty definitions then
       fields
     else
       ("$defs", `Assoc definitions) :: fields)
;;

let prepare_object fields =
  let open Result.Let_syntax in
  let%map definitions, values = prepare_schemas [ `Assoc fields ] in
  match values with
  | [ `Assoc fields ] -> attach_definitions definitions fields
  | _ -> assert false
;;

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

let checked_string
      ?format
      ?enum
      ?min_length
      ?max_length
      ?pattern
      ?content_encoding
      ?default
      ()
  =
  let open Result.Let_syntax in
  let format = Option.map format ~f:string_format_name in
  let%bind () = validate_format format in
  let%bind () =
    match content_encoding with
    | Some value when String.is_empty (String.strip value) ->
      Error "contentEncoding must not be empty"
    | _ -> Ok ()
  in
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
  (create
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
            ; field "pattern" (fun value -> `String value) pattern
            ; field "contentEncoding" (fun value -> `String value) content_encoding
            ; field "default" (fun value -> `String value) default
            ]))
   : string t)
;;

let validate_default_range ~compare ~minimum ~maximum = function
  | Some default
    when Option.exists minimum ~f:(fun minimum -> compare default minimum < 0)
         || Option.exists maximum ~f:(fun maximum -> compare default maximum > 0) ->
    Error "default must be within the declared range"
  | _ -> Ok ()
;;

let validate_numeric_constraints
      ~compare
      ~zero
      ~minimum
      ~maximum
      ~exclusive_minimum
      ~exclusive_maximum
      ~multiple_of
      ~default
  =
  let open Result.Let_syntax in
  let%bind () =
    match multiple_of with
    | Some value when compare value zero <= 0 ->
      Error "multipleOf must be greater than zero"
    | _ -> Ok ()
  in
  let strongest ~lower inclusive exclusive =
    match inclusive, exclusive with
    | None, None -> None
    | Some value, None -> Some (value, false)
    | None, Some value -> Some (value, true)
    | Some inclusive, Some exclusive ->
      if
        if lower then
          compare exclusive inclusive >= 0
        else
          compare exclusive inclusive <= 0
      then
        Some (exclusive, true)
      else
        Some (inclusive, false)
  in
  let lower = strongest ~lower:true minimum exclusive_minimum in
  let upper = strongest ~lower:false maximum exclusive_maximum in
  let%bind () =
    match lower, upper with
    | Some (lower, lower_strict), Some (upper, upper_strict)
      when compare lower upper > 0
           || (compare lower upper = 0 && (lower_strict || upper_strict)) ->
      Error "numeric bounds must describe a non-empty range"
    | _ -> Ok ()
  in
  match default with
  | Some value
    when Option.exists lower ~f:(fun (bound, strict) ->
           compare value bound < 0 || (strict && compare value bound = 0))
         || Option.exists upper ~f:(fun (bound, strict) ->
           compare value bound > 0 || (strict && compare value bound = 0)) ->
    Error "default must be within the declared bounds"
  | _ -> Ok ()
;;

let checked_integer
      ?format
      ?minimum
      ?maximum
      ?exclusive_minimum
      ?exclusive_maximum
      ?multiple_of
      ?default
      ()
  =
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
  let%bind () = validate_default_range ~compare:Int.compare ~minimum ~maximum default in
  let%map () =
    validate_numeric_constraints
      ~compare:Int.compare
      ~zero:0
      ~minimum
      ~maximum
      ~exclusive_minimum
      ~exclusive_maximum
      ~multiple_of
      ~default
  in
  (create
     (`Assoc
         (List.filter_opt
            [ Some ("type", `String "integer")
            ; field "format" (fun value -> `String value) format
            ; field "minimum" (fun value -> `Int value) minimum
            ; field "maximum" (fun value -> `Int value) maximum
            ; field "exclusiveMinimum" (fun value -> `Int value) exclusive_minimum
            ; field "exclusiveMaximum" (fun value -> `Int value) exclusive_maximum
            ; field "multipleOf" (fun value -> `Int value) multiple_of
            ; field "default" (fun value -> `Int value) default
            ]))
   : int t)
;;

let checked_int64
      ?format
      ?minimum
      ?maximum
      ?exclusive_minimum
      ?exclusive_maximum
      ?multiple_of
      ?default
      ()
  =
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
  let%bind () = validate_default_range ~compare:Int64.compare ~minimum ~maximum default in
  let%map () =
    validate_numeric_constraints
      ~compare:Int64.compare
      ~zero:0L
      ~minimum
      ~maximum
      ~exclusive_minimum
      ~exclusive_maximum
      ~multiple_of
      ~default
  in
  (create
     (`Assoc
         (List.filter_opt
            [ Some ("type", `String "integer")
            ; field "format" (fun value -> `String value) format
            ; field "minimum" (fun value -> `Intlit (Int64.to_string value)) minimum
            ; field "maximum" (fun value -> `Intlit (Int64.to_string value)) maximum
            ; field
                "exclusiveMinimum"
                (fun value -> `Intlit (Int64.to_string value))
                exclusive_minimum
            ; field
                "exclusiveMaximum"
                (fun value -> `Intlit (Int64.to_string value))
                exclusive_maximum
            ; field
                "multipleOf"
                (fun value -> `Intlit (Int64.to_string value))
                multiple_of
            ; field "default" (fun value -> `Intlit (Int64.to_string value)) default
            ]))
   : int64 t)
;;

let checked_number
      ?format
      ?minimum
      ?maximum
      ?exclusive_minimum
      ?exclusive_maximum
      ?multiple_of
      ?default
      ()
  =
  let open Result.Let_syntax in
  let format = Option.map format ~f:number_format_name in
  let%bind () = validate_format format in
  let%bind () = validate_float "minimum" minimum in
  let%bind () = validate_float "maximum" maximum in
  let%bind () = validate_float "exclusiveMinimum" exclusive_minimum in
  let%bind () = validate_float "exclusiveMaximum" exclusive_maximum in
  let%bind () = validate_float "multipleOf" multiple_of in
  let%bind () = validate_float "default" default in
  let%bind () =
    validate_range
      ~compare:Float.compare
      ~minimum_keyword:"minimum"
      ~maximum_keyword:"maximum"
      ~minimum
      ~maximum
  in
  let%bind () = validate_default_range ~compare:Float.compare ~minimum ~maximum default in
  let%map () =
    validate_numeric_constraints
      ~compare:Float.compare
      ~zero:0.
      ~minimum
      ~maximum
      ~exclusive_minimum
      ~exclusive_maximum
      ~multiple_of
      ~default
  in
  (create
     (`Assoc
         (List.filter_opt
            [ Some ("type", `String "number")
            ; field "format" (fun value -> `String value) format
            ; field "minimum" (fun value -> `Float value) minimum
            ; field "maximum" (fun value -> `Float value) maximum
            ; field "exclusiveMinimum" (fun value -> `Float value) exclusive_minimum
            ; field "exclusiveMaximum" (fun value -> `Float value) exclusive_maximum
            ; field "multipleOf" (fun value -> `Float value) multiple_of
            ; field "default" (fun value -> `Float value) default
            ]))
   : float t)
;;

let boolean ?default () : bool t =
  create
    (`Assoc
        (List.filter_opt
           [ Some ("type", `String "boolean")
           ; field "default" (fun value -> `Bool value) default
           ]))
;;

let checked_array
      ?min_items
      ?max_items
      ?prefix_items
      ?unique_items
      ?contains
      ?min_contains
      ?max_contains
      ~items
      ()
  =
  let open Result.Let_syntax in
  let%bind () = validate_non_negative "minItems" min_items in
  let%bind () = validate_non_negative "maxItems" max_items in
  let%bind () =
    validate_range
      ~compare:Int.compare
      ~minimum_keyword:"minItems"
      ~maximum_keyword:"maxItems"
      ~minimum:min_items
      ~maximum:max_items
  in
  let%bind () = validate_non_negative "minContains" min_contains in
  let%bind () = validate_non_negative "maxContains" max_contains in
  let%bind () =
    match contains, min_contains, max_contains with
    | None, None, None -> Ok ()
    | None, _, _ -> Error "minContains and maxContains require contains"
    | Some _, _, _ ->
      validate_range
        ~compare:Int.compare
        ~minimum_keyword:"minContains"
        ~maximum_keyword:"maxContains"
        ~minimum:(Some (Option.value min_contains ~default:1))
        ~maximum:max_contains
  in
  let%bind () =
    match prefix_items with
    | Some [] -> Error "prefixItems must not be empty"
    | _ -> Ok ()
  in
  let%map value =
    prepare_object
      (List.filter_opt
         [ Some ("type", `String "array")
         ; Some ("items", items.value)
         ; field "minItems" (fun value -> `Int value) min_items
         ; field "maxItems" (fun value -> `Int value) max_items
         ; field
             "prefixItems"
             (fun schemas -> `List (List.map schemas ~f:to_yojson))
             prefix_items
         ; field "uniqueItems" (fun value -> `Bool value) unique_items
         ; field "contains" to_yojson contains
         ; field "minContains" (fun value -> `Int value) min_contains
         ; field "maxContains" (fun value -> `Int value) max_contains
         ])
  in
  (create value : 'a array t)
;;

let checked_list
      ?min_items
      ?max_items
      ?prefix_items
      ?unique_items
      ?contains
      ?min_contains
      ?max_contains
      ~items
      ()
  =
  let open Result.Let_syntax in
  let%map schema =
    checked_array
      ?min_items
      ?max_items
      ?prefix_items
      ?unique_items
      ?contains
      ?min_contains
      ?max_contains
      ~items
      ()
  in
  (create schema.value : 'a list t)
;;

let dictionary ~values : (string * 'a) list t =
  create (`Assoc [ "type", `String "object"; "additionalProperties", values.value ])
;;

let nullable schema =
  let value = schema.value in
  let null = null.value in
  let nullable_value schema =
    let constraints_allow_null =
      match schema with
      | `Assoc fields ->
        let enum_allows_null =
          match List.Assoc.find fields "enum" ~equal:String.equal with
          | Some (`List values) -> List.mem values null ~equal:Poly.equal
          | Some _ -> false
          | None -> true
        in
        let const_allows_null =
          match List.Assoc.find fields "const" ~equal:String.equal with
          | Some value -> Poly.equal value null
          | None -> true
        in
        let any_of_allows_null =
          match member fields "anyOf" with
          | None -> true
          | Some (`List schemas) -> List.mem schemas null ~equal:Poly.equal
          | Some _ -> false
        in
        enum_allows_null
        && const_allows_null
        && any_of_allows_null
        && not
             (List.exists [ "allOf"; "oneOf"; "not"; "if"; "$ref" ] ~f:(fun name ->
                Option.is_some (member fields name)))
      | _ -> true
    in
    let already_nullable =
      constraints_allow_null
      &&
      match schema with
      | `Assoc fields ->
        (match List.Assoc.find fields "type" ~equal:String.equal with
         | Some (`String "null") -> true
         | Some (`List types) -> List.mem types (`String "null") ~equal:Poly.equal
         | None ->
           (match List.Assoc.find fields "anyOf" ~equal:String.equal with
            | Some (`List schemas) -> List.mem schemas null ~equal:Poly.equal
            | _ -> false)
         | _ -> false)
      | _ -> false
    in
    if already_nullable then
      schema
    else (
      match
        schema
      with
      | `Assoc _ when not constraints_allow_null ->
        `Assoc [ "anyOf", `List [ schema; null ] ]
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
  in
  create (nullable_value value)
;;

module Deriver = struct
  type polymorphic = { schema : 'a. 'a t }

  let polymorphic (Pack schema) =
    { schema =
        { value = schema.value
        ; schema_name = schema.schema_name
        ; description = schema.description
        ; tags = schema.tags
        }
    }
  ;;

  let any = create (`Bool true)

  type schema_type =
    | Array
    | Boolean
    | Integer
    | Null
    | Number
    | Object
    | String

  type nonrec additional_properties = additional_properties =
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

  let packed_schema (Pack schema) = to_yojson schema

  let type_schema schema_type : 'a t =
    create (`Assoc [ "type", `String (type_name schema_type) ])
  ;;

  let const_string value : 'a t = create (`Assoc [ "const", `String value ])
  let type_ref name : 'a t = create (`Assoc [ "$ref", `String ("#/$defs/" ^ name) ])

  let array ~items : 'a t =
    create (`Assoc [ "type", `String "array"; "items", packed_schema items ])
  ;;

  let tuple items : 'a t =
    let items = List.map items ~f:packed_schema in
    let length = List.length items in
    create
      (`Assoc
          [ "type", `String "array"
          ; "prefixItems", `List items
          ; "unevaluatedItems", `Bool false
          ; "minItems", `Int length
          ; "maxItems", `Int length
          ])
  ;;

  let any_of schemas : 'a t =
    create (`Assoc [ "anyOf", `List (List.map schemas ~f:packed_schema) ])
  ;;

  let one_of schemas : 'a t =
    create (`Assoc [ "oneOf", `List (List.map schemas ~f:packed_schema) ])
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
    create
      (`Assoc
          [ "type", `String "object"
          ; "properties", `Assoc properties
          ; "required", `List (List.map required ~f:(fun name -> `String name))
          ; "additionalProperties", additional_properties
          ])
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
    create
      (`Assoc
          [ ( "$defs"
            , `Assoc
                (List.map definitions ~f:(fun (name, schema) ->
                   name, packed_schema schema)) )
          ; "$ref", `String ("#/$defs/" ^ root)
          ])
  ;;

  let definitions schema =
    match schema.value with
    | `Assoc fields ->
      (match List.Assoc.find fields "$defs" ~equal:String.equal with
       | Some (`Assoc definitions) ->
         List.map definitions ~f:(fun (name, value) -> name, Pack (create value))
       | _ -> [])
    | _ -> []
  ;;

  let without_definitions schema =
    map_value schema ~f:(function
      | `Assoc fields ->
        `Assoc (List.filter fields ~f:(fun (name, _) -> not (String.equal name "$defs")))
      | value -> value)
  ;;

  let with_definitions extra schema =
    let definitions = merge_definitions (definitions schema) extra in
    if List.is_empty definitions then
      schema
    else
      map_value (without_definitions schema) ~f:(function
        | `Assoc fields ->
          `Assoc
            (( "$defs"
             , `Assoc
                 (List.map definitions ~f:(fun (name, schema) ->
                    name, packed_schema schema)) )
             :: fields)
        | value -> value)
  ;;

  let with_id id schema =
    if List.is_empty (definitions schema) then
      schema
    else
      map_value schema ~f:(function
        | `Assoc fields ->
          `Assoc
            (("$id", `String id)
             :: List.filter fields ~f:(fun (name, _) -> not (String.equal name "$id")))
        | value -> value)
  ;;

  let with_annotation name value schema =
    map_value schema ~f:(function
      | `Assoc fields ->
        `Assoc
          ((name, value)
           :: List.filter fields ~f:(fun (field, _) -> not (String.equal field name)))
      | schema -> `Assoc [ name, value; "allOf", `List [ schema ] ])
  ;;

  let with_title title schema = with_annotation "title" (`String title) schema

  let with_description description schema =
    with_annotation "description" (`String description) schema
  ;;

  let with_format_name_exn format schema =
    match validate_format (Some format) with
    | Error error -> Stdlib.invalid_arg error
    | Ok () -> with_annotation "format" (`String format) schema
  ;;

  let with_string_format_exn format schema =
    with_format_name_exn (string_format_name format) schema
  ;;

  let with_integer_format_exn format schema =
    with_format_name_exn (integer_format_name format) schema
  ;;

  let with_number_format_exn format schema =
    with_format_name_exn (number_format_name format) schema
  ;;

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

let valid_integer_literal value =
  let digits =
    if String.is_prefix value ~prefix:"-" then
      String.drop_prefix value 1
    else
      value
  in
  (not (String.is_empty digits))
  && String.for_all digits ~f:Char.is_digit
  && (String.length digits = 1 || not (Char.equal digits.[0] '0'))
;;

let rec validate_json ~context ~unique_names = function
  | `Assoc fields ->
    let open Result.Let_syntax in
    let%bind () =
      if unique_names then
        validate_unique_names "JSON object" (List.map fields ~f:fst)
      else
        Ok ()
    in
    List.fold_result fields ~init:() ~f:(fun () (_, value) ->
      validate_json ~context ~unique_names value)
  | `List values ->
    List.fold_result values ~init:() ~f:(fun () value ->
      validate_json ~context ~unique_names value)
  | `Float value when not (Float.is_finite value) ->
    Error (context ^ " must contain only finite floats")
  | `Intlit value when not (valid_integer_literal value) ->
    Error (context ^ " must contain only valid JSON integer literals")
  | `Null | `Bool _ | `Int _ | `Intlit _ | `Float _ | `String _ -> Ok ()
  | _ -> Error (context ^ " must contain only JSON values")
[@@warning "-11"]
;;

let validate_literal = validate_json ~context:"JSON value" ~unique_names:true

let checked_with_extension ~name ~value schema =
  let open Result.Let_syntax in
  let%bind () =
    if
      String.is_prefix name ~prefix:"x-"
      && String.length name > 2
      && not (String.exists name ~f:Char.is_whitespace)
    then
      Ok ()
    else
      Error "extension name must start with x-, have a non-empty suffix and no whitespace"
  in
  let%map () = validate_json ~context:"extension value" ~unique_names:false value in
  Deriver.with_annotation name value schema
;;

let with_extension ~name ~value schema =
  checked_with_extension ~name ~value schema |> unwrap
;;

let string ?format ?enum ?min_length ?max_length ?pattern ?content_encoding ?default () =
  checked_string
    ?format
    ?enum
    ?min_length
    ?max_length
    ?pattern
    ?content_encoding
    ?default
    ()
  |> unwrap
;;

let integer
      ?format
      ?minimum
      ?maximum
      ?exclusive_minimum
      ?exclusive_maximum
      ?multiple_of
      ?default
      ()
  =
  checked_integer
    ?format
    ?minimum
    ?maximum
    ?exclusive_minimum
    ?exclusive_maximum
    ?multiple_of
    ?default
    ()
  |> unwrap
;;

let int64
      ?format
      ?minimum
      ?maximum
      ?exclusive_minimum
      ?exclusive_maximum
      ?multiple_of
      ?default
      ()
  =
  checked_int64
    ?format
    ?minimum
    ?maximum
    ?exclusive_minimum
    ?exclusive_maximum
    ?multiple_of
    ?default
    ()
  |> unwrap
;;

let number
      ?format
      ?minimum
      ?maximum
      ?exclusive_minimum
      ?exclusive_maximum
      ?multiple_of
      ?default
      ()
  =
  checked_number
    ?format
    ?minimum
    ?maximum
    ?exclusive_minimum
    ?exclusive_maximum
    ?multiple_of
    ?default
    ()
  |> unwrap
;;

let array
      ?min_items
      ?max_items
      ?prefix_items
      ?unique_items
      ?contains
      ?min_contains
      ?max_contains
      ~items
      ()
  =
  checked_array
    ?min_items
    ?max_items
    ?prefix_items
    ?unique_items
    ?contains
    ?min_contains
    ?max_contains
    ~items
    ()
  |> unwrap
;;

let list
      ?min_items
      ?max_items
      ?prefix_items
      ?unique_items
      ?contains
      ?min_contains
      ?max_contains
      ~items
      ()
  =
  checked_list
    ?min_items
    ?max_items
    ?prefix_items
    ?unique_items
    ?contains
    ?min_contains
    ?max_contains
    ~items
    ()
  |> unwrap
;;

let compose keyword schemas =
  let open Result.Let_syntax in
  if List.is_empty schemas then
    Error (keyword ^ " must not be empty")
  else (
    let%map value = prepare_object [ keyword, `List schemas ] in
    create value)
;;

let checked_all_of schemas = compose "allOf" (List.map schemas ~f:to_yojson)
let all_of schemas = checked_all_of schemas |> unwrap
let checked_any_of schemas = compose "anyOf" (List.map schemas ~f:to_yojson)
let any_of schemas = checked_any_of schemas |> unwrap
let checked_one_of schemas = compose "oneOf" (List.map schemas ~f:to_yojson)
let one_of schemas = checked_one_of schemas |> unwrap

let checked_not schema =
  let open Result.Let_syntax in
  let%map value = prepare_object [ "not", schema.value ] in
  (create value : Yojson.Safe.t t)
;;

let not_ schema = checked_not schema |> unwrap

let constrain schema fields =
  let open Result.Let_syntax in
  let description =
    match schema.value with
    | `Assoc fields ->
      Option.map (member fields "description") ~f:(fun value -> "description", value)
    | _ -> None
  in
  let%map value =
    prepare_object
      (List.filter_opt
         [ description; Some ("allOf", `List [ schema.value; `Assoc fields ]) ])
  in
  map_value schema ~f:(fun _ -> value)
;;

let checked_with_not ~schema:excluded schema = constrain schema [ "not", excluded.value ]
let with_not ~schema:excluded schema = checked_with_not ~schema:excluded schema |> unwrap

let checked_if_then_else ~if_ ~then_ ~else_ =
  let open Result.Let_syntax in
  let%map value =
    prepare_object [ "if", if_.value; "then", then_.value; "else", else_.value ]
  in
  create value
;;

let if_then_else ~if_ ~then_ ~else_ = checked_if_then_else ~if_ ~then_ ~else_ |> unwrap

let object_constraints
      ?property_names
      ?(pattern_properties = [])
      ?min_properties
      ?max_properties
      ?(dependent_required = [])
      ?(dependent_schemas = [])
      ()
  =
  let open Result.Let_syntax in
  let%bind () = validate_non_negative "minProperties" min_properties in
  let%bind () = validate_non_negative "maxProperties" max_properties in
  let%bind () =
    validate_range
      ~compare:Int.compare
      ~minimum_keyword:"minProperties"
      ~maximum_keyword:"maxProperties"
      ~minimum:min_properties
      ~maximum:max_properties
  in
  let%bind () =
    validate_unique_names "patternProperties" (List.map pattern_properties ~f:fst)
  in
  let%bind () =
    validate_unique_names "dependentRequired" (List.map dependent_required ~f:fst)
  in
  let%bind () =
    validate_unique_names "dependentSchemas" (List.map dependent_schemas ~f:fst)
  in
  let%map () =
    List.fold_result dependent_required ~init:() ~f:(fun () (_, required) ->
      validate_unique_names "dependentRequired" required)
  in
  let schemas entries =
    `Assoc (List.map entries ~f:(fun (name, schema) -> name, to_yojson_packed schema))
  in
  let non_empty name entries f =
    if List.is_empty entries then
      None
    else
      Some (name, f entries)
  in
  List.filter_opt
    [ field "propertyNames" to_yojson property_names
    ; non_empty "patternProperties" pattern_properties schemas
    ; field "minProperties" (fun value -> `Int value) min_properties
    ; field "maxProperties" (fun value -> `Int value) max_properties
    ; non_empty "dependentRequired" dependent_required (fun entries ->
        `Assoc
          (List.map entries ~f:(fun (name, required) ->
             name, `List (List.map required ~f:(fun value -> `String value)))))
    ; non_empty "dependentSchemas" dependent_schemas schemas
    ]
;;

let checked_object
      ?(properties = [])
      ?(required = [])
      ?(additional_properties = Allow)
      ?property_names
      ?pattern_properties
      ?min_properties
      ?max_properties
      ?dependent_required
      ?dependent_schemas
      ()
  =
  let open Result.Let_syntax in
  let%bind () = validate_unique_names "properties" (List.map properties ~f:fst) in
  let%bind () = validate_unique_names "required" required in
  let%bind constraints =
    object_constraints
      ?property_names
      ?pattern_properties
      ?min_properties
      ?max_properties
      ?dependent_required
      ?dependent_schemas
      ()
  in
  let additional_properties =
    match additional_properties with
    | Allow -> `Bool true
    | Deny -> `Bool false
    | Schema schema -> to_yojson_packed schema
  in
  let%map value =
    prepare_object
      ([ "type", `String "object"
       ; ( "properties"
         , `Assoc
             (List.map properties ~f:(fun (name, schema) -> name, to_yojson_packed schema))
         )
       ; "required", `List (List.map required ~f:(fun name -> `String name))
       ; "additionalProperties", additional_properties
       ]
       @ constraints)
  in
  (create value : Yojson.Safe.t t)
;;

let object_
      ?properties
      ?required
      ?additional_properties
      ?property_names
      ?pattern_properties
      ?min_properties
      ?max_properties
      ?dependent_required
      ?dependent_schemas
      ()
  =
  checked_object
    ?properties
    ?required
    ?additional_properties
    ?property_names
    ?pattern_properties
    ?min_properties
    ?max_properties
    ?dependent_required
    ?dependent_schemas
    ()
  |> unwrap
;;

let checked_with_dictionary_constraints
      ?property_names
      ?pattern_properties
      ?min_properties
      ?max_properties
      ?dependent_required
      ?dependent_schemas
      schema
  =
  let open Result.Let_syntax in
  let pattern_properties =
    Option.map
      pattern_properties
      ~f:(List.map ~f:(fun (name, schema) -> name, pack schema))
  in
  let%bind constraints =
    object_constraints
      ?property_names
      ?pattern_properties
      ?min_properties
      ?max_properties
      ?dependent_required
      ?dependent_schemas
      ()
  in
  if List.is_empty constraints then
    Ok schema
  else
    constrain schema constraints
;;

let with_dictionary_constraints
      ?property_names
      ?pattern_properties
      ?min_properties
      ?max_properties
      ?dependent_required
      ?dependent_schemas
      schema
  =
  checked_with_dictionary_constraints
    ?property_names
    ?pattern_properties
    ?min_properties
    ?max_properties
    ?dependent_required
    ?dependent_schemas
    schema
  |> unwrap
;;

(* Decimal keys compare JSON numbers without converting full-width integers to
   floats. Object order and numeric spelling do not distinguish enum values. *)
let decimal_key value =
  let negative = String.is_prefix value ~prefix:"-" in
  let value =
    if negative then
      String.drop_prefix value 1
    else
      value
  in
  let mantissa, exponent =
    match String.lsplit2 (String.lowercase value) ~on:'e' with
    | Some (mantissa, exponent) -> mantissa, Int.of_string exponent
    | None -> value, 0
  in
  let integral, fractional =
    match String.lsplit2 mantissa ~on:'.' with
    | Some pair -> pair
    | None -> mantissa, ""
  in
  let digits = String.lstrip (integral ^ fractional) ~drop:(Char.equal '0') in
  let significant = String.rstrip digits ~drop:(Char.equal '0') in
  if String.is_empty significant then
    "0"
  else
    (if negative then
       "-"
     else
       "")
    ^ significant
    ^ "e"
    ^ Int.to_string
        (exponent
         - String.length fractional
         + String.length digits
         - String.length significant)
;;

let numeric_key = function
  | `Int value -> Some (decimal_key (Int.to_string value))
  | `Intlit value -> Some (decimal_key value)
  | `Float value -> Some (decimal_key (Float.to_string value))
  | _ -> None
;;

let rec literal_equal left right =
  match numeric_key left, numeric_key right with
  | Some left, Some right -> String.equal left right
  | _ ->
    (match left, right with
     | `List left, `List right -> List.equal literal_equal left right
     | `Assoc left, `Assoc right ->
       let sort =
         List.sort ~compare:(fun (left, _) (right, _) -> String.compare left right)
       in
       List.equal
         (fun (lk, lv) (rk, rv) -> String.equal lk rk && literal_equal lv rv)
         (sort left)
         (sort right)
     | _ -> Yojson.Safe.equal left right)
;;

let checked_with_enum ~encode values schema =
  let open Result.Let_syntax in
  if List.is_empty values then
    Error "enum must not be empty"
  else (
    let values = List.map values ~f:encode in
    let%bind () =
      List.fold_result values ~init:() ~f:(fun () value -> validate_literal value)
    in
    let%bind _ =
      List.fold_result values ~init:[] ~f:(fun seen value ->
        if List.mem seen value ~equal:literal_equal then
          Error "enum contains duplicate JSON value"
        else
          Ok (value :: seen))
    in
    constrain schema [ "enum", `List values ])
;;

let with_enum ~encode values schema = checked_with_enum ~encode values schema |> unwrap

let checked_with_const ~encode value schema =
  let open Result.Let_syntax in
  let value = encode value in
  let%bind () = validate_literal value in
  constrain schema [ "const", value ]
;;

let with_const ~encode value schema = checked_with_const ~encode value schema |> unwrap
let with_title = Deriver.with_title
let with_description = Deriver.with_description

let with_deprecated value schema =
  Deriver.with_annotation "deprecated" (`Bool value) schema
;;

let with_read_only value schema = Deriver.with_annotation "readOnly" (`Bool value) schema

let with_write_only value schema =
  Deriver.with_annotation "writeOnly" (`Bool value) schema
;;

let checked_with_examples ~encode values schema =
  let open Result.Let_syntax in
  let values = List.map values ~f:encode in
  let%map () =
    List.fold_result values ~init:() ~f:(fun () value -> validate_literal value)
  in
  Deriver.with_annotation "examples" (`List values) schema
;;

let with_examples ~encode values schema =
  checked_with_examples ~encode values schema |> unwrap
;;

let checked_with_discriminator ~property_name ?(mapping = []) schema =
  let open Result.Let_syntax in
  let%bind () = validate_unique_names "discriminator mapping" (List.map mapping ~f:fst) in
  let%bind () =
    match schema.value with
    | `Assoc fields
      when List.exists [ "allOf"; "anyOf"; "oneOf" ] ~f:(fun name ->
             Option.is_some (member fields name)) ->
      (match member fields "type" with
       | Some (`String kind) when not (String.equal kind "object") ->
         Error "discriminator requires an object composition"
       | _ -> Ok ())
    | _ -> Error "discriminator requires allOf, anyOf or oneOf"
  in
  let value =
    `Assoc
      ([ "propertyName", `String property_name ]
       @
       if List.is_empty mapping then
         []
       else
         [ ( "mapping"
           , `Assoc (List.map mapping ~f:(fun (name, target) -> name, `String target)) )
         ])
  in
  Ok (Deriver.with_annotation "discriminator" value schema)
;;

let with_discriminator ~property_name ?mapping schema =
  checked_with_discriminator ~property_name ?mapping schema |> unwrap
;;

module Unsafe = struct
  let rec validate : Yojson.Safe.t -> Yojson.Safe.t = function
    | `Assoc fields ->
      `Assoc (List.map fields ~f:(fun (name, value) -> name, validate value))
    | `List values -> `List (List.map values ~f:validate)
    | `Intlit value -> `Intlit value
    | (`Null | `Bool _ | `Int _ | `Float _ | `String _) as value -> value
    | _ -> Stdlib.invalid_arg "JSON Schema must contain only JSON values"
  [@@warning "-11"]
  ;;

  let of_yojson value = create (validate value)
end
