open Ppxlib
open! Base
module List = Stdlib.List
module Option = Stdlib.Option
module String = Stdlib.String

type config =
  { schema_namespace : string
  ; ocaml_doc : bool
  ; strict : bool
  ; decoder_strict : bool option
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

let check_format_expression expr =
  match expr.pexp_desc with
  | Pexp_variant
      ("Custom", Some { pexp_desc = Pexp_constant (Pconst_string (name, _, _)); _ }) ->
    if Base.String.is_empty (Base.String.strip name) then
      Location.raise_errorf
        ~loc:expr.pexp_loc
        "typed-endpoint-ppx: Custom format must not be empty"
  | Pexp_variant ("Custom", _) ->
    Location.raise_errorf
      ~loc:expr.pexp_loc
      "typed-endpoint-ppx: use (`Custom \"my-format\") with a string literal"
  | Pexp_variant (_, None) -> ()
  | _ ->
    Location.raise_errorf
      ~loc:expr.pexp_loc
      "typed-endpoint-ppx: format expects a variant literal, e.g. `Date_time or (`Custom \"my-format\"); string formats are no longer supported"
;;

let validate_annotations type_declarations =
  let add seen name loc =
    if List.mem name seen then
      Location.raise_errorf
        ~loc
        "typed-endpoint-ppx: duplicate JSON Schema annotation '%s' on the same node"
        name;
    name :: seen
  in
  let check attrs =
    let check_attr seen attr =
      let removed replacement =
        Location.raise_errorf
          ~loc:attr.attr_loc
          "typed-endpoint-ppx: [@%s] has been removed; %s"
          attr.attr_name.txt
          replacement
      in
      (* Attribute.declare also accepts the unqualified suffix of its name. *)
      let name =
        match attr.attr_name.txt with
        | ( "title"
          | "description"
          | "format"
          | "minimum"
          | "maximum"
          | "attrs"
          | "allow_extra_fields"
          | "disallow_extra_fields"
          | "ref"
          | "compact_variants" ) as name -> "jsonschema." ^ name
        | name -> name
      in
      match name with
      | "jsonschema.key" -> removed "use [@key ...] shared with Yojson"
      | "jsonschema.name" -> removed "use [@name ...] shared with Yojson"
      | "jsonschema.default" -> removed "use [@default ...] shared with Yojson"
      | "jsonschema.option" -> removed "use [@default None] shared with Yojson"
      | "jsonschema.ref" ->
        removed
          "define the field type's <type>_jsonschema instead of an unchecked reference"
      | "jsonschema.compact_variants" ->
        removed
          "variants always use Yojson arrays, including [\"Tag\"] for empty constructors"
      | "jsonschema.attrs" ->
        let seen = add seen "attrs" attr.attr_loc in
        (match attr.attr_payload with
         | PStr
             [ { pstr_desc = Pstr_eval ({ pexp_desc = Pexp_record (fields, None); _ }, _)
               ; _
               }
             ] ->
           List.fold_left
             (fun seen ({ txt; loc }, value) ->
                match txt with
                | Lident name ->
                  let seen = add seen name loc in
                  if String.equal name "format" then
                    check_format_expression value;
                  seen
                | _ -> seen)
             seen
             fields
         | _ -> seen)
      | ( "jsonschema.title"
        | "jsonschema.description"
        | "jsonschema.format"
        | "jsonschema.minimum"
        | "jsonschema.maximum"
        | "jsonschema.allow_extra_fields"
        | "jsonschema.disallow_extra_fields" ) as name ->
        let seen =
          add seen (String.sub name 11 (String.length name - 11)) attr.attr_loc
        in
        if String.equal name "jsonschema.format" then (
          match
            attr.attr_payload
          with
          | PStr [ { pstr_desc = Pstr_eval (expr, _); _ } ] ->
            check_format_expression expr
          | _ -> ());
        seen
      | _ -> seen
    in
    ignore (List.fold_left check_attr [] attrs)
  in
  let visitor =
    object
      inherit Ast_traverse.iter as super

      method! attributes attrs =
        check attrs;
        super#attributes attrs
    end
  in
  List.iter visitor#type_declaration type_declarations
;;

let deriving_generators type_declarations =
  let generators expr =
    match expr.pexp_desc with
    | Pexp_tuple expressions -> expressions
    | _ -> [ expr ]
  in
  let from_attribute attr =
    match attr.attr_name.txt, attr.attr_payload with
    | ( ("deriving" | "deriving_inline" | "ppxlib.deriving" | "ppxlib.deriving_inline")
      , PStr [ { pstr_desc = Pstr_eval (expr, _); _ } ] ) -> generators expr
    | _ -> []
  in
  List.concat_map
    (fun td -> List.concat_map from_attribute td.ptype_attributes)
    type_declarations
  |> List.filter_map (fun expr ->
    match expr.pexp_desc with
    | Pexp_ident { txt = Lident name; _ } -> Some (name, [])
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident name; _ }; _ }, args) ->
      Some (name, args)
    | _ -> None)
;;

let yojson_strict generators =
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
  List.find_map
    (fun (name, args) ->
       match name with
       | "yojson" | "of_yojson" ->
         Some (Option.value (strict_argument args) ~default:true)
       | _ -> None)
    generators
;;

let string_attr name ctx =
  Attribute.declare name ctx Ast_pattern.(single_expr_payload (estring __')) (fun x -> x)
;;

let expr_attr name ctx =
  Attribute.declare name ctx Ast_pattern.(single_expr_payload __) (fun x -> x)
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
  expr_attr "jsonschema.format" Attribute.Context.type_declaration
;;

let jsonschema_ld_format =
  expr_attr "jsonschema.format" Attribute.Context.label_declaration
;;

let jsonschema_ct_format = expr_attr "jsonschema.format" Attribute.Context.core_type

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
  [ Attribute.T jsonschema_td_allow_extra_fields
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
  ]
;;

let resolve_additional_properties ~loc ~strict ~decoder_strict ~allow ~disallow =
  let explicit =
    match allow, disallow with
    | true, true ->
      Location.raise_errorf
        ~loc
        "typed-endpoint-ppx: [@jsonschema.allow_extra_fields] and [@jsonschema.disallow_extra_fields] are mutually exclusive"
    | true, false -> Some true
    | false, true -> Some false
    | false, false -> None
  in
  (match explicit, decoder_strict with
   | Some allow, Some strict when Bool.equal allow strict ->
     Location.raise_errorf
       ~loc
       "typed-endpoint-ppx: additionalProperties conflicts with Yojson strict = %b; configure the decoder instead"
       strict
   | _ -> ());
  Option.value explicit ~default:(not strict)
;;

let configure
      ~loc
      type_declarations
      removed_tuple_flag
      ocaml_doc
      strict
      no_yojson
      schema_namespace
  =
  validate_annotations type_declarations;
  if removed_tuple_flag then
    Location.raise_errorf
      ~loc
      "typed-endpoint-ppx: polymorphic_variant_tuple has been removed; tuple arguments always follow Yojson's flattened encoding";
  let generators = deriving_generators type_declarations in
  let has_yojson =
    List.exists
      (fun (name, _) -> List.mem name [ "yojson"; "to_yojson"; "of_yojson" ])
      generators
  in
  if not (has_yojson || Option.value no_yojson ~default:false) then
    Location.raise_errorf
      ~loc
      "typed-endpoint-ppx: jsonschema requires yojson, to_yojson or of_yojson in the same type declaration group; add a codec deriver or use jsonschema { no_yojson = true }";
  let decoder_strict = yojson_strict generators in
  (match strict, decoder_strict with
   | Some schema_strict, Some decoder_strict
     when not (Bool.equal schema_strict decoder_strict) ->
     Location.raise_errorf
       ~loc
       "typed-endpoint-ppx: jsonschema strict = %b conflicts with Yojson strict = %b; configure the decoder instead"
       schema_strict
       decoder_strict
   | _ -> ());
  let strict =
    Option.value decoder_strict ~default:(Option.value strict ~default:false)
  in
  let check ~loc allow disallow =
    ignore (resolve_additional_properties ~loc ~strict ~decoder_strict ~allow ~disallow)
  in
  let visitor =
    object
      inherit Ast_traverse.iter as super

      method! type_declaration td =
        check
          ~loc:td.ptype_loc
          (Option.is_some (Attribute.get jsonschema_td_allow_extra_fields td))
          (Option.is_some (Attribute.get jsonschema_td_disallow_extra_fields td));
        super#type_declaration td

      method! constructor_declaration cd =
        check
          ~loc:cd.pcd_loc
          (Option.is_some (Attribute.get jsonschema_cd_allow_extra_fields cd))
          (Option.is_some (Attribute.get jsonschema_cd_disallow_extra_fields cd));
        super#constructor_declaration cd
    end
  in
  List.iter visitor#type_declaration type_declarations;
  { schema_namespace; ocaml_doc; strict; decoder_strict }
;;

let args () =
  (* Recognize the removed flag only to report its migration diagnostic. *)
  Deriving.Args.(
    empty
    +> flag "polymorphic_variant_tuple"
    +> flag "ocaml_doc"
    +> arg "strict" (ebool __)
    +> arg "no_yojson" (ebool __))
;;
