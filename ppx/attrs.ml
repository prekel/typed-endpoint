open Ppxlib
open! Base
module List = Stdlib.List
module Option = Stdlib.Option
module String = Stdlib.String

type config =
  { polymorphic_variant_tuple : bool
  ; ocaml_doc : bool
  ; strict : bool
  }

let find_raw_attr names attrs =
  List.find_opt (fun attr -> List.mem attr.attr_name.txt names) attrs
;;

let parse_attribute pattern attr =
  match Ast_pattern.parse_res pattern attr.attr_loc attr Stdlib.Fun.id with
  | Ok value -> Some value
  | Error _ -> None
;;

let parse_raw_attr payload_pattern attr =
  let pattern =
    Ast_pattern.(attribute ~name:(string attr.attr_name.txt) ~payload:payload_pattern)
  in
  parse_attribute pattern attr
;;

let yojson_key attrs =
  Option.bind
    (find_raw_attr [ "key"; "deriving.yojson.key" ] attrs)
    (fun attr -> parse_raw_attr Ast_pattern.(single_expr_payload (estring __')) attr)
;;

let yojson_name attrs =
  Option.bind
    (find_raw_attr [ "name"; "deriving.yojson.name" ] attrs)
    (fun attr -> parse_raw_attr Ast_pattern.(single_expr_payload (estring __')) attr)
;;

let yojson_default attrs =
  Option.bind
    (find_raw_attr [ "default"; "deriving.yojson.default" ] attrs)
    (fun attr -> parse_raw_attr Ast_pattern.(single_expr_payload __) attr)
;;

let string_attr name ctx =
  Attribute.declare name ctx Ast_pattern.(single_expr_payload (estring __')) (fun x -> x)
;;

let expr_attr name ctx =
  Attribute.declare name ctx Ast_pattern.(single_expr_payload __) (fun x -> x)
;;

let jsonschema_key = string_attr "jsonschema.key" Attribute.Context.label_declaration
let jsonschema_ref = string_attr "jsonschema.ref" Attribute.Context.label_declaration

let jsonschema_variant_name =
  string_attr "jsonschema.name" Attribute.Context.constructor_declaration
;;

let jsonschema_polymorphic_variant_name =
  string_attr "jsonschema.name" Attribute.Context.rtag
;;

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

let jsonschema_option =
  Attribute.declare_flag "jsonschema.option" Attribute.Context.label_declaration
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

let jsonschema_ld_default =
  expr_attr "jsonschema.default" Attribute.Context.label_declaration
;;

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

let ld_key (ld : label_declaration) =
  match Attribute.get jsonschema_key ld with
  | Some _ as key -> key
  | None -> yojson_key ld.pld_attributes
;;

let cd_name (cd : constructor_declaration) =
  match Attribute.get jsonschema_variant_name cd with
  | Some _ as name -> name
  | None -> yojson_name cd.pcd_attributes
;;

let rtag_name (rtag : row_field) =
  match Attribute.get jsonschema_polymorphic_variant_name rtag with
  | Some _ as name -> name
  | None -> yojson_name rtag.prf_attributes
;;

let ld_default (ld : label_declaration) =
  match Attribute.get jsonschema_ld_default ld with
  | Some _ as default -> default
  | None -> yojson_default ld.pld_attributes
;;

let attributes =
  [ Attribute.T jsonschema_key
  ; Attribute.T jsonschema_ref
  ; Attribute.T jsonschema_variant_name
  ; Attribute.T jsonschema_polymorphic_variant_name
  ; Attribute.T jsonschema_td_allow_extra_fields
  ; Attribute.T jsonschema_cd_allow_extra_fields
  ; Attribute.T jsonschema_td_disallow_extra_fields
  ; Attribute.T jsonschema_cd_disallow_extra_fields
  ; Attribute.T jsonschema_option
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
  ; Attribute.T jsonschema_ld_default
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
