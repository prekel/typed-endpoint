open! Base
open Ppxlib
open Ast_builder.Default

let fail ~loc message = Location.raise_errorf ~loc "mapper: %s" message

let expand ~fallible ~loc:_ ~path:_ expression =
  match expression with
  | [%expr fun ([%p? argument] : [%t? source_type]) -> ([%e? body] : [%t? target])] ->
    let source =
      match argument.ppat_desc with
      | Ppat_var name -> Some name.txt
      | Ppat_record (_, Closed) -> None
      | _ ->
        fail ~loc:argument.ppat_loc "expected a source variable or closed record pattern"
    in
    let fields =
      match body.pexp_desc with
      | Pexp_record (fields, None) -> fields
      | _ -> fail ~loc:body.pexp_loc "expected a complete target record"
    in
    let fields =
      List.map fields ~f:(fun (label, value) ->
        let copied =
          match label.txt, value.pexp_desc with
          | Longident.Lident field, Pexp_ident { txt = Lident name; _ } ->
            String.equal field name
          | _ -> false
        in
        let loc = value.pexp_loc in
        let value =
          if copied then (
            match
              source
            with
            | Some source -> pexp_field ~loc (evar ~loc source) label
            | None ->
              fail ~loc "record-pattern mappings require explicit field expressions")
          else
            value
        in
        let value =
          if fallible && copied then
            [%expr Base.Result.return [%e value]]
          else
            value
        in
        label, value)
    in
    let body = Record_mapping.record ~loc:body.pexp_loc ~target ~fallible fields in
    let loc = expression.pexp_loc in
    let result = [%expr fun ([%p argument] : [%t source_type]) -> [%e body]] in
    (match source with
     | Some _ -> result
     | None -> [%expr [%e result] [@warning "+9"] [@warnerror "+9"]])
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
             (expand ~fallible:false))
      ; Context_free.Rule.extension
          (Extension.declare
             "mapper_result"
             Extension.Context.expression
             Ast_pattern.(single_expr_payload __)
             (expand ~fallible:true))
      ]
;;

let () = Mapper_deriver.register ()
