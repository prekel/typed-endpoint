open Ppxlib
open! Base
module List = Stdlib.List
module Option = Stdlib.Option
module String = Stdlib.String

type config =
  { schema_namespace : string
  ; polymorphic_variant_tuple : bool
  ; ocaml_doc : bool
  ; strict : bool
  }

let find_raw_attr names attrs =
  List.fold_left
    (fun best attr ->
       match List.mem attr.attr_name.txt names, best with
       | false, _ -> best
       | true, None -> Some attr
       | true, Some previous ->
         let length = String.length attr.attr_name.txt in
         let previous_length = String.length previous.attr_name.txt in
         if length > previous_length then
           Some attr
         else if length < previous_length then
           best
         else
           Location.raise_errorf ~loc:attr.attr_loc "Duplicated attribute")
    None
    attrs
;;

let parse_attribute pattern attr =
  match Ast_pattern.parse_res pattern attr.attr_loc attr Stdlib.Fun.id with
  | Ok value -> Some value
  | Error _ -> None
;;

let yojson_attribute name payload_pattern attrs =
  Option.map
    (fun attr ->
       let pattern =
         Ast_pattern.(
           attribute ~name:(string attr.attr_name.txt) ~payload:payload_pattern)
       in
       Attribute.mark_as_handled_manually attr;
       Ast_pattern.parse pattern attr.attr_loc attr Stdlib.Fun.id)
    (find_raw_attr [ name; "yojson." ^ name; "deriving.yojson." ^ name ] attrs)
;;

let yojson_key = yojson_attribute "key" Ast_pattern.(single_expr_payload (estring __'))
let yojson_name = yojson_attribute "name" Ast_pattern.(single_expr_payload (estring __'))
let yojson_default = yojson_attribute "default" Ast_pattern.(single_expr_payload __)

let yojson_encoding =
  yojson_attribute
    "encoding"
    Ast_pattern.(
      single_expr_payload
        (pexp_variant (map0 (string "string") ~f:`String) none
         ||| pexp_variant (map0 (string "number") ~f:`Number) none))
;;

let string_encoded (core_type : core_type) =
  match core_type with
  | [%type: int64] | [%type: Int64.t] | [%type: nativeint] | [%type: Nativeint.t] ->
    (match yojson_encoding core_type.ptyp_attributes with
     | Some `String -> true
     | Some `Number | None -> false)
  | _ -> false
;;

let reject_removed_annotations type_declarations =
  let visitor =
    object
      inherit Ast_traverse.iter as super

      method! attribute attr =
        let replacement =
          match attr.attr_name.txt with
          | "jsonschema.key" -> Some "[@key ...]"
          | "jsonschema.name" -> Some "[@name ...]"
          | "jsonschema.default" -> Some "[@default ...]"
          | "jsonschema.option" -> Some "[@default None]"
          | _ -> None
        in
        match replacement with
        | Some replacement ->
          Location.raise_errorf
            ~loc:attr.attr_loc
            "typed-endpoint-ppx: [@%s] has been removed; use %s shared with Yojson"
            attr.attr_name.txt
            replacement
        | None -> super#attribute attr
    end
  in
  List.iter visitor#type_declaration type_declarations
;;

let yojson_strict type_declarations =
  let bool_value expr =
    match expr.pexp_desc with
    | Pexp_construct ({ txt = Lident "true"; _ }, None) -> Some true
    | Pexp_construct ({ txt = Lident "false"; _ }, None) -> Some false
    | _ -> None
  in
  let strict_argument args =
    List.find_map
      (fun (label, expr) ->
         match label with
         | Labelled "strict" -> bool_value expr
         | _ ->
           (match expr.pexp_desc with
            | Pexp_record (fields, None) ->
              List.find_map
                (fun ({ txt = field; _ }, value) ->
                   match field with
                   | Lident "strict" -> bool_value value
                   | _ -> None)
                fields
            | _ -> None))
      args
  in
  let yojson_generator expr =
    let name_and_args =
      match expr.pexp_desc with
      | Pexp_ident { txt = Lident name; _ } -> Some (name, [])
      | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident name; _ }; _ }, args) ->
        Some (name, args)
      | _ -> None
    in
    match name_and_args with
    | Some ("yojson", args) | Some ("of_yojson", args) ->
      Some (Option.value (strict_argument args) ~default:true)
    | _ -> None
  in
  let generators expr =
    match expr.pexp_desc with
    | Pexp_tuple expressions -> expressions
    | _ -> [ expr ]
  in
  let strict_from_attribute attr =
    match attr.attr_payload with
    | PStr [ { pstr_desc = Pstr_eval (expr, _); _ } ] ->
      List.find_map yojson_generator (generators expr)
    | _ -> None
  in
  List.find_map
    (fun type_declaration ->
       List.find_map
         (fun attr ->
            match attr.attr_name.txt with
            | "deriving"
            | "deriving_inline"
            | "ppxlib.deriving"
            | "ppxlib.deriving_inline" -> strict_from_attribute attr
            | _ -> None)
         type_declaration.ptype_attributes)
    type_declarations
;;

let string_attr name ctx =
  Attribute.declare name ctx Ast_pattern.(single_expr_payload (estring __')) (fun x -> x)
;;

let expr_attr name ctx =
  Attribute.declare name ctx Ast_pattern.(single_expr_payload __) (fun x -> x)
;;

let jsonschema_ref = string_attr "jsonschema.ref" Attribute.Context.label_declaration

let jsonschema_td_allow_extra_fields =
  Attribute.declare
    "jsonschema.allow_extra_fields"
    Attribute.Context.type_declaration
    Ast_pattern.(pstr nil)
    (fun () -> ())
;;

let jsonschema_cd_allow_extra_fields =
  Attribute.declare
    "jsonschema.allow_extra_fields"
    Attribute.Context.constructor_declaration
    Ast_pattern.(pstr nil)
    (fun () -> ())
;;

let jsonschema_td_disallow_extra_fields =
  Attribute.declare
    "jsonschema.disallow_extra_fields"
    Attribute.Context.type_declaration
    Ast_pattern.(pstr nil)
    (fun () -> ())
;;

let jsonschema_cd_disallow_extra_fields =
  Attribute.declare
    "jsonschema.disallow_extra_fields"
    Attribute.Context.constructor_declaration
    Ast_pattern.(pstr nil)
    (fun () -> ())
;;

let jsonschema_ld_description =
  string_attr "jsonschema.description" Attribute.Context.label_declaration
;;

let jsonschema_td_description =
  string_attr "jsonschema.description" Attribute.Context.type_declaration
;;

let jsonschema_cd_description =
  string_attr "jsonschema.description" Attribute.Context.constructor_declaration
;;

let jsonschema_ct_description =
  string_attr "jsonschema.description" Attribute.Context.core_type
;;

let jsonschema_rtag_description =
  string_attr "jsonschema.description" Attribute.Context.rtag
;;

let jsonschema_ld_title =
  string_attr "jsonschema.title" Attribute.Context.label_declaration
;;

let jsonschema_td_title =
  string_attr "jsonschema.title" Attribute.Context.type_declaration
;;

let jsonschema_cd_title =
  string_attr "jsonschema.title" Attribute.Context.constructor_declaration
;;

let jsonschema_ct_title = string_attr "jsonschema.title" Attribute.Context.core_type
let jsonschema_rtag_title = string_attr "jsonschema.title" Attribute.Context.rtag

let jsonschema_td_format =
  string_attr "jsonschema.format" Attribute.Context.type_declaration
;;

let jsonschema_ld_format =
  string_attr "jsonschema.format" Attribute.Context.label_declaration
;;

let jsonschema_ct_format = string_attr "jsonschema.format" Attribute.Context.core_type

let jsonschema_td_maximum =
  expr_attr "jsonschema.maximum" Attribute.Context.type_declaration
;;

let jsonschema_ld_maximum =
  expr_attr "jsonschema.maximum" Attribute.Context.label_declaration
;;

let jsonschema_ct_maximum = expr_attr "jsonschema.maximum" Attribute.Context.core_type

let jsonschema_td_minimum =
  expr_attr "jsonschema.minimum" Attribute.Context.type_declaration
;;

let jsonschema_ld_minimum =
  expr_attr "jsonschema.minimum" Attribute.Context.label_declaration
;;

let jsonschema_ct_minimum = expr_attr "jsonschema.minimum" Attribute.Context.core_type
let jsonschema_ct_attrs = expr_attr "jsonschema.attrs" Attribute.Context.core_type
let jsonschema_td_attrs = expr_attr "jsonschema.attrs" Attribute.Context.type_declaration
let jsonschema_ld_attrs = expr_attr "jsonschema.attrs" Attribute.Context.label_declaration

let doc_attr_pattern =
  Ast_pattern.(
    attribute
      ~name:(string "ocaml.doc" ||| string "doc")
      ~payload:(single_expr_payload (estring __')))
;;

let find_doc_attr attrs =
  let matches =
    List.filter_map
      (fun attr ->
         parse_attribute doc_attr_pattern attr
         |> Option.map (fun ({ txt; loc } : string Location.loc) ->
           { txt = String.trim txt; loc }))
      attrs
  in
  match matches with
  | [] -> None
  | [ single ] -> Some single
  | first :: _ as all ->
    Some { txt = String.concat "\n\n" (List.map (fun x -> x.txt) all); loc = first.loc }
;;

let fallback_description ~ocaml_doc explicit_desc attrs node =
  match Attribute.get explicit_desc node with
  | Some _ as x -> x
  | None ->
    if ocaml_doc then
      find_doc_attr attrs
    else
      None
;;

let ld_description ~ocaml_doc (ld : label_declaration) =
  fallback_description ~ocaml_doc jsonschema_ld_description ld.pld_attributes ld
;;

let td_description ~ocaml_doc (td : type_declaration) =
  fallback_description ~ocaml_doc jsonschema_td_description td.ptype_attributes td
;;

let cd_description ~ocaml_doc (cd : constructor_declaration) =
  fallback_description ~ocaml_doc jsonschema_cd_description cd.pcd_attributes cd
;;

let ct_description ~ocaml_doc (ct : core_type) =
  fallback_description ~ocaml_doc jsonschema_ct_description ct.ptyp_attributes ct
;;

let rtag_description ~ocaml_doc (rf : row_field) =
  fallback_description ~ocaml_doc jsonschema_rtag_description rf.prf_attributes rf
;;

let ld_title (ld : label_declaration) = Attribute.get jsonschema_ld_title ld
let td_title (td : type_declaration) = Attribute.get jsonschema_td_title td
let cd_title (cd : constructor_declaration) = Attribute.get jsonschema_cd_title cd
let ct_title (ct : core_type) = Attribute.get jsonschema_ct_title ct
let rtag_title (rf : row_field) = Attribute.get jsonschema_rtag_title rf

let jsonschema_td_compact_variants =
  Attribute.declare_flag "jsonschema.compact_variants" Attribute.Context.type_declaration
;;

let ld_key (ld : label_declaration) = yojson_key ld.pld_attributes
let cd_name (cd : constructor_declaration) = yojson_name cd.pcd_attributes
let rtag_name (rtag : row_field) = yojson_name rtag.prf_attributes

let ld_default (ld : label_declaration) =
  match yojson_default ld.pld_attributes with
  | Some _ as default -> default
  | None -> yojson_default ld.pld_type.ptyp_attributes
;;

let field_type (ld : label_declaration) =
  let encoding_attributes =
    List.filter
      (fun attr ->
         List.mem
           attr.attr_name.txt
           [ "encoding"; "yojson.encoding"; "deriving.yojson.encoding" ])
      ld.pld_attributes
  in
  { ld.pld_type with ptyp_attributes = ld.pld_type.ptyp_attributes @ encoding_attributes }
;;

let attributes =
  [ Attribute.T jsonschema_ref
  ; Attribute.T jsonschema_td_allow_extra_fields
  ; Attribute.T jsonschema_cd_allow_extra_fields
  ; Attribute.T jsonschema_td_disallow_extra_fields
  ; Attribute.T jsonschema_cd_disallow_extra_fields
  ; Attribute.T jsonschema_ld_description
  ; Attribute.T jsonschema_td_description
  ; Attribute.T jsonschema_cd_description
  ; Attribute.T jsonschema_ct_description
  ; Attribute.T jsonschema_rtag_description
  ; Attribute.T jsonschema_ld_title
  ; Attribute.T jsonschema_td_title
  ; Attribute.T jsonschema_cd_title
  ; Attribute.T jsonschema_ct_title
  ; Attribute.T jsonschema_rtag_title
  ; Attribute.T jsonschema_td_format
  ; Attribute.T jsonschema_ld_format
  ; Attribute.T jsonschema_ct_format
  ; Attribute.T jsonschema_td_maximum
  ; Attribute.T jsonschema_ld_maximum
  ; Attribute.T jsonschema_ct_maximum
  ; Attribute.T jsonschema_td_minimum
  ; Attribute.T jsonschema_ld_minimum
  ; Attribute.T jsonschema_ct_minimum
  ; Attribute.T jsonschema_ct_attrs
  ; Attribute.T jsonschema_td_attrs
  ; Attribute.T jsonschema_ld_attrs
  ; Attribute.T jsonschema_td_compact_variants
  ]
;;

let args () =
  Deriving.Args.(
    empty
    +> flag "polymorphic_variant_tuple"
    +> flag "ocaml_doc"
    +> arg "strict" (ebool __))
;;
