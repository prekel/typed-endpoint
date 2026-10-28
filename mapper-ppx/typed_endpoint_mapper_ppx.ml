open! Base
open Ppxlib
open Ast_builder.Default

let fail ~loc message = Location.raise_errorf ~loc "mapper: %s" message

let expand ~loc:_ ~path:_ expression =
  match expression with
  | [%expr fun ([%p? argument] : [%t? source_type]) -> ([%e? body] : [%t? target])] ->
    let source =
      match argument.ppat_desc with
      | Ppat_var name -> name.txt
      | _ -> fail ~loc:argument.ppat_loc "expected a source variable"
    in
    let fields =
      match body.pexp_desc with
      | Pexp_record (fields, None) -> fields
      | _ -> fail ~loc:body.pexp_loc "expected a complete target record"
    in
    let fields =
      List.map fields ~f:(fun (label, value) ->
        let value =
          match label.txt, value.pexp_desc with
          | Longident.Lident field, Pexp_ident { txt = Lident name; _ }
            when String.equal field name
                 && Poly.equal label.loc.loc_start value.pexp_loc.loc_start
                 && Poly.equal label.loc.loc_end value.pexp_loc.loc_end ->
            pexp_field ~loc:value.pexp_loc (evar ~loc:value.pexp_loc source) label
          | _ -> value
        in
        label, value)
    in
    let body =
      pexp_constraint
        ~loc:body.pexp_loc
        (pexp_record ~loc:body.pexp_loc fields None)
        target
    in
    let loc = expression.pexp_loc in
    [%expr fun ([%p argument] : [%t source_type]) -> [%e body]]
  | _ ->
    fail
      ~loc:expression.pexp_loc
      "expected fun (source : Source.t) -> ({ fields } : Target.t)"
;;

let () =
  Driver.register_transformation
    "typed_endpoint_mapper"
    ~rules:
      [ Context_free.Rule.extension
          (Extension.declare
             "mapper"
             Extension.Context.expression
             Ast_pattern.(single_expr_payload __)
             expand)
      ]
;;
