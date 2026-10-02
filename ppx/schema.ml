open Ppxlib
open! Base
open Ast_builder.Default
module List = Stdlib.List
module Option = Stdlib.Option
module String = Stdlib.String

let call ~loc name args =
  let name = "Typed_endpoint.Json_schema.Deriver." ^ name in
  pexp_apply ~loc (pexp_ident ~loc { txt = Longident.parse name; loc }) args
;;

let pack ~loc schema = [%expr Typed_endpoint.Json_schema.pack [%e schema]]
let packed_list ~loc schemas = elist ~loc (List.map (pack ~loc) schemas)
let const ~loc value = call ~loc "const_string" [ Nolabel, estring ~loc value ]
let type_ref ~loc type_name = call ~loc "type_ref" [ Nolabel, estring ~loc type_name ]

let type_def ~loc type_name =
  let constructor =
    match type_name with
    | "array" -> "Array"
    | "boolean" -> "Boolean"
    | "integer" -> "Integer"
    | "null" -> "Null"
    | "number" -> "Number"
    | "object" -> "Object"
    | "string" -> "String"
    | _ ->
      Location.raise_errorf
        ~loc
        "typed-endpoint-ppx: unknown JSON Schema type %S"
        type_name
  in
  let schema_type =
    pexp_construct
      ~loc
      { txt = Longident.parse ("Typed_endpoint.Json_schema.Deriver." ^ constructor); loc }
      None
  in
  call ~loc "type_schema" [ Nolabel, schema_type ]
;;

let array ~loc item = call ~loc "array" [ Labelled "items", pack ~loc item ]

let string_lengths ~loc ?minimum ?maximum schema =
  let minimum_arg =
    Option.map (fun value -> Labelled "minimum", eint ~loc value) minimum
  in
  let maximum_arg =
    Option.map (fun value -> Labelled "maximum", eint ~loc value) maximum
  in
  call
    ~loc
    "with_string_lengths"
    (List.filter_map Stdlib.Fun.id [ minimum_arg; maximum_arg ] @ [ Nolabel, schema ])
;;

let nullable ~loc schema = [%expr Typed_endpoint.Json_schema.nullable [%e schema]]
let any_of ~loc values = call ~loc "any_of" [ Nolabel, packed_list ~loc values ]
let one_of ~loc values = call ~loc "one_of" [ Nolabel, packed_list ~loc values ]
let tuple ~loc elements = call ~loc "tuple" [ Nolabel, packed_list ~loc elements ]

let record ~loc ~properties ~required ~allow_extra_fields =
  let policy_name =
    if allow_extra_fields then
      "Allow"
    else
      "Deny"
  in
  let policy =
    pexp_construct
      ~loc
      { txt = Longident.parse ("Typed_endpoint.Json_schema.Deriver." ^ policy_name); loc }
      None
  in
  call
    ~loc
    "record"
    [ Labelled "properties", elist ~loc properties
    ; Labelled "required", elist ~loc (List.map (estring ~loc) required)
    ; Labelled "additional_properties", policy
    ]
;;

let title ~loc title schema =
  call ~loc "with_title" [ Nolabel, estring ~loc title; Nolabel, schema ]
;;

let description ~loc description schema =
  call ~loc "with_description" [ Nolabel, estring ~loc description; Nolabel, schema ]
;;

let format ~loc format schema =
  call ~loc "with_format" [ Nolabel, estring ~loc format; Nolabel, schema ]
;;

let minimum_int ~loc value schema =
  call ~loc "with_minimum_int" [ Nolabel, value; Nolabel, schema ]
;;

let minimum_number ~loc value schema =
  call ~loc "with_minimum_number" [ Nolabel, value; Nolabel, schema ]
;;

let maximum_int ~loc value schema =
  call ~loc "with_maximum_int" [ Nolabel, value; Nolabel, schema ]
;;

let maximum_number ~loc value schema =
  call ~loc "with_maximum_number" [ Nolabel, value; Nolabel, schema ]
;;

let default ~loc value schema =
  call ~loc "with_default" [ Nolabel, value; Nolabel, schema ]
;;

let variants ~loc ?(compact_variants = false) constrs =
  let opt_title_and_description ~loc title_opt description_opt schema =
    let schema =
      match title_opt with
      | Some title_text -> title ~loc title_text schema
      | None -> schema
    in
    match description_opt with
    | Some description_text -> description ~loc description_text schema
    | None -> schema
  in
  any_of
    ~loc
    (List.map
       (function
         | `Tag (name, typs, description_opt, title_opt) ->
           let schema =
             if compact_variants && List.length typs = 0 then
               const ~loc name
             else
               tuple ~loc (const ~loc name :: typs)
           in
           opt_title_and_description ~loc title_opt description_opt schema
         | `Inherit typ -> typ)
       constrs)
;;

let result ~loc error ok =
  variants ~loc [ `Tag ("Error", [ error ], None, None); `Tag ("Ok", [ ok ], None, None) ]
;;

module Annotation = struct
  let add_schema_attr (attr, node) f schema =
    match Attribute.get attr node with
    | Some v -> f v schema
    | None -> schema
  ;;

  let add_title_attr ~loc attr schema =
    add_schema_attr
      attr
      (fun title_value schema -> title ~loc title_value.txt schema)
      schema
  ;;

  let add_format ~loc attr core_type =
    add_schema_attr attr (fun fmt schema ->
      match core_type with
      | [%type: string] | [%type: bytes] | [%type: string option] | [%type: bytes option]
        -> format ~loc fmt.txt schema
      | _ ->
        Location.raise_errorf
          ~loc:core_type.ptyp_loc
          "[@jsonschema.format] can only be applied to string or bytes types")
  ;;

  let add_maximum ~loc attr core_type =
    add_schema_attr attr (fun expr schema ->
      match core_type, expr.pexp_desc with
      | [%type: int], Pexp_constant (Pconst_integer _)
      | [%type: int32], Pexp_constant (Pconst_integer _)
      | [%type: nativeint], Pexp_constant (Pconst_integer _) ->
        maximum_int ~loc expr schema
      | [%type: float], Pexp_constant (Pconst_float _) -> maximum_number ~loc expr schema
      | _ ->
        Location.raise_errorf
          ~loc:core_type.ptyp_loc
          "[@jsonschema.maximum] can only be applied to numeric types")
  ;;

  let add_minimum ~loc attr core_type =
    add_schema_attr attr (fun expr schema ->
      match core_type, expr.pexp_desc with
      | [%type: int], Pexp_constant (Pconst_integer _)
      | [%type: int32], Pexp_constant (Pconst_integer _)
      | [%type: nativeint], Pexp_constant (Pconst_integer _) ->
        minimum_int ~loc expr schema
      | [%type: float], Pexp_constant (Pconst_float _) -> minimum_number ~loc expr schema
      | _ ->
        Location.raise_errorf
          ~loc:core_type.ptyp_loc
          "[@jsonschema.minimum] can only be applied to numeric types")
  ;;

  let rec serialize_expr ~loc ct default_value_expr =
    match ct with
    | [%type: int] -> [%expr `Int [%e default_value_expr]]
    | [%type: int32] -> [%expr `Intlit (Int32.to_string [%e default_value_expr])]
    | [%type: int64] -> [%expr `Intlit (Int64.to_string [%e default_value_expr])]
    | [%type: nativeint] -> [%expr `Intlit (Nativeint.to_string [%e default_value_expr])]
    | [%type: float] -> [%expr `Float [%e default_value_expr]]
    | [%type: string] -> [%expr `String [%e default_value_expr]]
    | [%type: bytes] -> [%expr `String (Stdlib.Bytes.to_string [%e default_value_expr])]
    | [%type: char] -> [%expr `String (Stdlib.String.make 1 [%e default_value_expr])]
    | [%type: bool] -> [%expr `Bool [%e default_value_expr]]
    | [%type: unit] -> [%expr `Null]
    | [%type: Yojson.Safe.t] | [%type: Yojson.Safe.json] -> default_value_expr
    | [%type: [%t? t] option] ->
      [%expr
        match [%e default_value_expr] with
        | None -> `Null
        | Some ppx_opt_v -> [%e serialize_expr ~loc t [%expr ppx_opt_v]]]
    | [%type: [%t? t] list] ->
      [%expr
        `List
          (Stdlib.List.map
             (fun ppx_item -> [%e serialize_expr ~loc t [%expr ppx_item]])
             [%e default_value_expr])]
    | [%type: [%t? t] array] ->
      [%expr
        `List
          (Stdlib.Array.to_list
             (Stdlib.Array.map
                (fun ppx_item -> [%e serialize_expr ~loc t [%expr ppx_item]])
                [%e default_value_expr]))]
    | { ptyp_desc = Ptyp_tuple types; _ } ->
      let vars = List.mapi (fun i _ -> Stdlib.Printf.sprintf "ppx_tuple_%d" i) types in
      let pats = List.map (fun v -> ppat_var ~loc { txt = v; loc }) vars in
      let exprs = List.map2 (fun t v -> serialize_expr ~loc t (evar ~loc v)) types vars in
      [%expr
        match [%e default_value_expr] with
        | [%p ppat_tuple ~loc pats] -> `List [%e elist ~loc exprs]]
    | { ptyp_desc = Ptyp_var _; _ } ->
      Location.raise_errorf
        ~loc:ct.ptyp_loc
        "[@default] for a type parameter requires an explicit JSON value"
    | { ptyp_desc = Ptyp_constr (id, args); _ } ->
      let arg_serializers =
        List.map
          (fun arg -> [%expr fun ppx_x -> [%e serialize_expr ~loc arg [%expr ppx_x]]])
          args
      in
      let to_json_expr =
        type_constr_conv
          ~loc
          id
          ~f:(fun s ->
            if String.equal s "t" then
              "to_yojson"
            else
              s ^ "_to_yojson")
          arg_serializers
      in
      [%expr [%e to_json_expr] [%e default_value_expr]]
    | _ ->
      Location.raise_errorf
        ~loc:ct.ptyp_loc
        "[@default] cannot serialize this type. For non-primitive types, ensure a '<type>_to_yojson' function is in scope (e.g., add [@@deriving yojson] to the type definition)"
  ;;

  let add_default ~loc default_attr core_type schema =
    match default_attr with
    | None -> schema
    | Some expr ->
      let json_value =
        match core_type, expr.pexp_desc with
        | [%type: [%t? _] option], Pexp_construct ({ txt = Lident "None"; _ }, None) ->
          [%expr `Null]
        | [%type: [%t? t] option], Pexp_construct ({ txt = Lident "Some"; _ }, Some value)
          -> serialize_expr ~loc t value
        | _, Pexp_construct ({ txt = Lident "[]"; _ }, None) -> [%expr `List []]
        | _ -> serialize_expr ~loc core_type expr
      in
      default ~loc json_value schema
  ;;

  let add_description ~loc desc_opt schema =
    match desc_opt with
    | Some desc -> description ~loc desc.txt schema
    | None -> schema
  ;;

  let add_title ~loc title_opt schema =
    match title_opt with
    | Some title_text -> title ~loc title_text.txt schema
    | None -> schema
  ;;

  let add_annotations ~loc ?core_type attrs schema =
    let require_core_type field =
      match core_type with
      | Some t -> t
      | None ->
        Location.raise_errorf
          ~loc
          "[@jsonschema.attrs] '%s' requires a type context (use the individual [@jsonschema.%s] attribute instead)"
          field
          field
    in
    match attrs with
    | None -> schema
    | Some expr ->
      (match expr.pexp_desc with
       | Pexp_record (fields, None) ->
         List.fold_left
           (fun schema ({ txt = label; loc = label_loc }, value) ->
              match label with
              | Lident "title" ->
                (match value.pexp_desc with
                 | Pexp_constant (Pconst_string (s, _, _)) -> title ~loc s schema
                 | _ ->
                   Location.raise_errorf
                     ~loc:value.pexp_loc
                     "[@jsonschema.attrs] 'title' must be a string literal")
              | Lident "description" ->
                (match value.pexp_desc with
                 | Pexp_constant (Pconst_string (s, _, _)) -> description ~loc s schema
                 | _ ->
                   Location.raise_errorf
                     ~loc:value.pexp_loc
                     "[@jsonschema.attrs] 'description' must be a string literal")
              | Lident "format" ->
                let ct = require_core_type "format" in
                (match value.pexp_desc with
                 | Pexp_constant (Pconst_string (s, _, _)) ->
                   (match ct with
                    | [%type: string]
                    | [%type: bytes]
                    | [%type: string option]
                    | [%type: bytes option] -> format ~loc s schema
                    | _ ->
                      Location.raise_errorf
                        ~loc:ct.ptyp_loc
                        "[@jsonschema.attrs] 'format' can only be applied to string types")
                 | _ ->
                   Location.raise_errorf
                     ~loc:value.pexp_loc
                     "[@jsonschema.attrs] 'format' must be a string literal")
              | Lident "maximum" ->
                let ct = require_core_type "maximum" in
                (match ct with
                 | [%type: int] | [%type: int32] | [%type: nativeint] ->
                   maximum_int ~loc value schema
                 | [%type: float] -> maximum_number ~loc value schema
                 | _ ->
                   Location.raise_errorf
                     ~loc:ct.ptyp_loc
                     "[@jsonschema.attrs] 'maximum' can only be applied to numeric types")
              | Lident "minimum" ->
                let ct = require_core_type "minimum" in
                (match ct with
                 | [%type: int] | [%type: int32] | [%type: nativeint] ->
                   minimum_int ~loc value schema
                 | [%type: float] -> minimum_number ~loc value schema
                 | _ ->
                   Location.raise_errorf
                     ~loc:ct.ptyp_loc
                     "[@jsonschema.attrs] 'minimum' can only be applied to numeric types")
              | Lident name ->
                Location.raise_errorf
                  ~loc:label_loc
                  "[@jsonschema.attrs] unknown field: '%s'"
                  name
              | _ ->
                Location.raise_errorf
                  ~loc:label_loc
                  "[@jsonschema.attrs] expected a simple field name")
           schema
           fields
       | _ ->
         Location.raise_errorf
           ~loc:expr.pexp_loc
           "[@jsonschema.attrs] expects a record expression: { field = value; ... }")
  ;;
end
