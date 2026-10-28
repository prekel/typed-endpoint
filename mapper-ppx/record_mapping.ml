open! Base
open Ppxlib
open Ast_builder.Default

let fresh_names expression =
  let used = ref (Set.empty (module String)) in
  let visitor =
    object
      inherit Ast_traverse.iter as super

      method! expression expression =
        (match expression.pexp_desc with
         | Pexp_ident { txt = Lident name; _ } -> used := Set.add !used name
         | _ -> ());
        super#expression expression

      method! pattern pattern =
        (match pattern.ppat_desc with
         | Ppat_var name -> used := Set.add !used name.txt
         | _ -> ());
        super#pattern pattern
    end
  in
  visitor#expression expression;
  let rec fresh () =
    let name = gen_symbol ~prefix:"mapper_field" () in
    if Set.mem !used name then
      fresh ()
    else (
      used := Set.add !used name;
      name)
  in
  fresh
;;

let record ~loc ~target ~fallible fields =
  let body = pexp_constraint ~loc (pexp_record ~loc fields None) target in
  if not fallible then
    body
  else (
    let loc = body.pexp_loc in
    let fresh = fresh_names (pexp_record ~loc fields None) in
    let bindings = List.map fields ~f:(fun (label, value) -> label, value, fresh ()) in
    let result =
      pexp_constraint
        ~loc
        (pexp_record
           ~loc
           (List.map bindings ~f:(fun (label, _, name) -> label, evar ~loc name))
           None)
        target
    in
    List.fold_right
      bindings
      ~init:[%expr Base.Result.return [%e result]]
      ~f:(fun (label, value, name) rest ->
        let field = Longident.last_exn label.txt in
        [%expr
          Base.Result.bind
            (Typed_endpoint_mapper.Mapping_error.at_field
               [%e estring ~loc field]
               [%e value])
            ~f:(fun [%p pvar ~loc name] -> [%e rest])]))
;;
