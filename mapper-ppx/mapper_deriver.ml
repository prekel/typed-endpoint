open! Base
open Ppxlib
open Ast_builder.Default

let fail ~loc message = Location.raise_errorf ~loc "mapper_from: %s" message

let field_attribute =
  Attribute.declare
    "@mapper.from.field"
    Attribute.Context.label_declaration
    Ast_pattern.(single_expr_payload (estring __))
    Fn.id
;;

let convert_attribute =
  Attribute.declare
    "@mapper.from.convert"
    Attribute.Context.label_declaration
    Ast_pattern.(single_expr_payload __)
    Fn.id
;;

let compute_attribute =
  Attribute.declare
    "@mapper.from.compute"
    Attribute.Context.label_declaration
    Ast_pattern.(single_expr_payload __)
    Fn.id
;;

let source_type ~loc = function
  | Some { pexp_desc = Pexp_extension ({ txt = "type"; _ }, PTyp typ); _ } -> typ
  | _ -> fail ~loc "expected source = [%type: Domain.t]"
;;

let fields td =
  if not (List.is_empty td.ptype_params) then
    fail ~loc:td.ptype_loc "parameterized DTOs are not supported";
  if Poly.equal td.ptype_private Private then
    fail ~loc:td.ptype_loc "private DTOs are not supported";
  match td.ptype_kind with
  | Ptype_record fields -> fields
  | _ -> fail ~loc:td.ptype_loc "expected a record declaration"
;;

let function_name td =
  if String.equal td.ptype_name.txt "t" then
    "of_domain"
  else
    td.ptype_name.txt ^ "_of_domain"
;;

let specifications td =
  List.map (fields td) ~f:(fun field ->
    let renamed = Attribute.get field_attribute field in
    let convert = Attribute.get convert_attribute field in
    let compute = Attribute.get compute_attribute field in
    if Option.is_some compute && (Option.is_some renamed || Option.is_some convert) then
      fail ~loc:field.pld_loc "compute cannot be combined with field or convert";
    let name = Option.value renamed ~default:field.pld_name.txt in
    if
      String.is_empty name
      || (not (Char.is_lowercase name.[0] || Char.equal name.[0] '_'))
      || not
           (String.for_all name ~f:(fun c ->
              Char.is_alphanum c || Char.equal c '_' || Char.equal c '\''))
    then
      fail ~loc:field.pld_loc "field must be an unqualified OCaml record label";
    field, name, convert, compute)
;;

let structure ~ctxt (_, declarations) source =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let source_type = source_type ~loc source in
  List.map declarations ~f:(fun td ->
    let loc = td.ptype_loc in
    let specs = specifications td in
    let converters =
      List.concat_map specs ~f:(fun (_, _, convert, compute) ->
        Option.to_list convert @ Option.to_list compute)
    in
    let source = Record_mapping.fresh_names (pexp_tuple ~loc converters) () in
    let source_expression = evar ~loc source in
    let fields =
      List.map specs ~f:(fun (field, name, convert, compute) ->
        let loc = field.pld_loc in
        let value =
          match compute with
          | Some f -> pexp_apply ~loc f [ Nolabel, source_expression ]
          | None ->
            let value = pexp_field ~loc source_expression (Located.lident ~loc name) in
            (match convert with
             | None -> value
             | Some f -> pexp_apply ~loc f [ Nolabel, value ])
        in
        Located.lident ~loc field.pld_name.txt, value)
    in
    let target = ptyp_constr ~loc (Located.lident ~loc td.ptype_name.txt) [] in
    let body = Record_mapping.record ~loc ~target ~fallible:false fields in
    let expression =
      [%expr fun ([%p pvar ~loc source] : [%t source_type]) -> [%e body]]
    in
    pstr_value
      ~loc
      Nonrecursive
      [ value_binding ~loc ~pat:(pvar ~loc (function_name td)) ~expr:expression ])
;;

let signature ~ctxt (_, declarations) source =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let source = source_type ~loc source in
  List.map declarations ~f:(fun td ->
    ignore (specifications td);
    let loc = td.ptype_loc in
    let target = ptyp_constr ~loc (Located.lident ~loc td.ptype_name.txt) [] in
    psig_value
      ~loc
      (value_description
         ~loc
         ~name:(Located.mk ~loc (function_name td))
         ~type_:(ptyp_arrow ~loc Nolabel source target)
         ~prim:[]))
;;

let args () = Deriving.Args.(empty +> arg "source" __)

let register () =
  ignore
    (Deriving.add
       "mapper_from"
       ~str_type_decl:(Deriving.Generator.V2.make (args ()) structure)
       ~sig_type_decl:(Deriving.Generator.V2.make (args ()) signature))
;;
