open! Base
open Ppxlib
open Ast_builder.Default

type direction =
  | From
  | Into

let deriver_name = function
  | From -> "mapper_from"
  | Into -> "mapper_into"
;;

let fail direction ~loc message =
  Location.raise_errorf ~loc "%s: %s" (deriver_name direction) message
;;

let declare_expression name =
  Attribute.declare
    name
    Attribute.Context.label_declaration
    Ast_pattern.(single_expr_payload __)
    Fn.id
;;

let declare_field name =
  Attribute.declare
    name
    Attribute.Context.label_declaration
    Ast_pattern.(single_expr_payload (estring __))
    Fn.id
;;

type attributes =
  { field : (label_declaration, string) Attribute.t
  ; convert : (label_declaration, expression) Attribute.t
  ; result : (label_declaration, expression) Attribute.t
  ; compute : (label_declaration, expression) Attribute.t option
  ; skip : (label_declaration, unit) Attribute.t option
  }

let from_attributes =
  { field = declare_field "@mapper.from.field"
  ; convert = declare_expression "@mapper.from.convert"
  ; result = declare_expression "@mapper.from.result"
  ; compute = Some (declare_expression "@mapper.from.compute")
  ; skip = None
  }
;;

let into_attributes =
  { field = declare_field "@mapper.into.field"
  ; convert = declare_expression "@mapper.into.convert"
  ; result = declare_expression "@mapper.into.result"
  ; compute = None
  ; skip =
      Some
        (Attribute.declare
           "@mapper.into.skip"
           Attribute.Context.label_declaration
           Ast_pattern.(pstr nil)
           ())
  }
;;

let other_type direction ~loc = function
  | Some { pexp_desc = Pexp_extension ({ txt = "type"; _ }, PTyp typ); _ } ->
    let visitor =
      object
        inherit Ast_traverse.iter as super

        method! core_type typ =
          (match typ.ptyp_desc with
           | Ptyp_var _ | Ptyp_any ->
             fail
               direction
               ~loc:typ.ptyp_loc
               "source and target types must be monomorphic"
           | _ -> ());
          super#core_type typ
      end
    in
    visitor#core_type typ;
    typ
  | _ ->
    fail
      direction
      ~loc
      (match direction with
       | From -> "expected source = [%type: Domain.t]"
       | Into -> "expected target = [%type: Domain.t]")
;;

let fields direction td =
  if not (List.is_empty td.ptype_params) then
    fail direction ~loc:td.ptype_loc "parameterized DTOs are not supported";
  if Poly.equal td.ptype_private Private then
    fail direction ~loc:td.ptype_loc "private DTOs are not supported";
  match td.ptype_kind with
  | Ptype_record fields -> fields
  | _ -> fail direction ~loc:td.ptype_loc "expected a record declaration"
;;

let function_name direction td =
  let suffix =
    match direction with
    | From -> "of_domain"
    | Into -> "to_domain"
  in
  if String.equal td.ptype_name.txt "t" then
    suffix
  else
    td.ptype_name.txt ^ "_" ^ suffix
;;

type specification =
  { field : label_declaration
  ; source_name : string
  ; target_name : string
  ; converter : expression option
  ; compute : expression option
  ; returns_result : bool
  }

let specifications direction ~fallible td =
  let attrs =
    match direction with
    | From -> from_attributes
    | Into -> into_attributes
  in
  let specs =
    List.filter_map (fields direction td) ~f:(fun field ->
      let prefix, supported =
        match direction with
        | From ->
          ( "mapper.from."
          , [ "mapper.from.field"
            ; "mapper.from.convert"
            ; "mapper.from.result"
            ; "mapper.from.compute"
            ] )
        | Into ->
          ( "mapper.into."
          , [ "mapper.into.field"
            ; "mapper.into.convert"
            ; "mapper.into.result"
            ; "mapper.into.skip"
            ] )
      in
      List.iter field.pld_attributes ~f:(fun attribute ->
        if
          String.is_prefix attribute.attr_name.txt ~prefix
          && not (List.mem supported attribute.attr_name.txt ~equal:String.equal)
        then
          fail
            direction
            ~loc:attribute.attr_loc
            ("unknown mapping attribute " ^ attribute.attr_name.txt));
      let renamed = Attribute.get attrs.field field in
      let convert = Attribute.get attrs.convert field in
      let result = Attribute.get attrs.result field in
      let compute = Option.bind attrs.compute ~f:(fun attr -> Attribute.get attr field) in
      let skip =
        Option.bind attrs.skip ~f:(fun attr -> Attribute.get attr field) |> Option.is_some
      in
      let error message = fail direction ~loc:field.pld_loc message in
      if Option.is_some convert && Option.is_some result then
        error "convert cannot be combined with result";
      if
        Option.is_some compute
        && (Option.is_some renamed || Option.is_some convert || Option.is_some result)
      then
        error "compute cannot be combined with field, convert or result";
      if
        skip && (Option.is_some renamed || Option.is_some convert || Option.is_some result)
      then
        error "skip cannot be combined with field, convert or result";
      if Option.is_some result && not fallible then
        error "result requires fallible = true";
      let name = Option.value renamed ~default:field.pld_name.txt in
      if
        String.is_empty name
        || (not (Char.is_lowercase name.[0] || Char.equal name.[0] '_'))
        || not
             (String.for_all name ~f:(fun c ->
                Char.is_alphanum c || Char.equal c '_' || Char.equal c '\''))
      then
        error "field must be an unqualified OCaml record label";
      if skip then
        None
      else (
        let source_name, target_name =
          match direction with
          | From -> name, field.pld_name.txt
          | Into -> field.pld_name.txt, name
        in
        Some
          { field
          ; source_name
          ; target_name
          ; converter =
              (match result with
               | Some _ -> result
               | None -> convert)
          ; compute
          ; returns_result = Option.is_some result
          }))
  in
  if List.is_empty specs then
    fail direction ~loc:td.ptype_loc "at least one mapped field is required";
  let _ =
    List.fold
      specs
      ~init:(Set.empty (module String))
      ~f:(fun names spec ->
        if Set.mem names spec.target_name then
          fail
            direction
            ~loc:spec.field.pld_loc
            ("duplicate target field " ^ spec.target_name);
        Set.add names spec.target_name)
  in
  specs
;;

let types direction td other =
  let dto =
    ptyp_constr ~loc:td.ptype_loc (Located.lident ~loc:td.ptype_loc td.ptype_name.txt) []
  in
  match direction with
  | From -> other, dto
  | Into -> dto, other
;;

let structure direction ~ctxt (_, declarations) other fallible =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let other = other_type direction ~loc other in
  let fallible = Option.value fallible ~default:false in
  List.map declarations ~f:(fun td ->
    let loc = td.ptype_loc in
    let specs = specifications direction ~fallible td in
    let converters =
      List.concat_map specs ~f:(fun spec ->
        Option.to_list spec.converter @ Option.to_list spec.compute)
    in
    let source = Record_mapping.fresh_names (pexp_tuple ~loc converters) () in
    let source_expression = evar ~loc source in
    let fields =
      List.map specs ~f:(fun spec ->
        let loc = spec.field.pld_loc in
        let value =
          match spec.compute with
          | Some f -> pexp_apply ~loc f [ Nolabel, source_expression ]
          | None ->
            let value =
              pexp_field ~loc source_expression (Located.lident ~loc spec.source_name)
            in
            (match spec.converter with
             | None -> value
             | Some f -> pexp_apply ~loc f [ Nolabel, value ])
        in
        let value =
          if fallible && not spec.returns_result then
            [%expr Base.Result.return [%e value]]
          else
            value
        in
        Located.lident ~loc spec.target_name, value)
    in
    let source_type, target = types direction td other in
    let body = Record_mapping.record ~loc ~target ~fallible fields in
    let expression =
      [%expr fun ([%p pvar ~loc source] : [%t source_type]) -> [%e body]]
    in
    pstr_value
      ~loc
      Nonrecursive
      [ value_binding ~loc ~pat:(pvar ~loc (function_name direction td)) ~expr:expression
      ])
;;

let signature direction ~ctxt (_, declarations) other fallible =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let other = other_type direction ~loc other in
  let fallible = Option.value fallible ~default:false in
  List.map declarations ~f:(fun td ->
    ignore (specifications direction ~fallible td);
    let loc = td.ptype_loc in
    let source, target = types direction td other in
    let target =
      if fallible then
        [%type: ([%t target], Typed_endpoint_mapper.Mapping_error.t) Base.Result.t]
      else
        target
    in
    psig_value
      ~loc
      (value_description
         ~loc
         ~name:(Located.mk ~loc (function_name direction td))
         ~type_:(ptyp_arrow ~loc Nolabel source target)
         ~prim:[]))
;;

let args direction =
  Deriving.Args.(
    empty
    +> arg
         (match direction with
          | From -> "source"
          | Into -> "target")
         __
    +> arg "fallible" (ebool __))
;;

let register () =
  List.iter [ From; Into ] ~f:(fun direction ->
    ignore
      (Deriving.add
         (deriver_name direction)
         ~str_type_decl:
           (Deriving.Generator.V2.make (args direction) (structure direction))
         ~sig_type_decl:
           (Deriving.Generator.V2.make (args direction) (signature direction))))
;;
