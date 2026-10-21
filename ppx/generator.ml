open Ppxlib
open! Base
open Ast_builder.Default
module List = Stdlib.List
module Option = Stdlib.Option
module String = Stdlib.String

let schema_id ~namespace ~loc =
  estring
    ~loc
    (Printf.sprintf
       "urn:typed-endpoint:schema:%s:%d:%d"
       namespace
       loc.loc_start.pos_lnum
       (loc.loc_start.pos_cnum - loc.loc_start.pos_bol))
;;

let deriver_name = "jsonschema"

let schema_type ~loc typ =
  ptyp_constr
    ~loc
    { txt = Ldot (Ldot (Lident "Typed_endpoint", "Json_schema"), "t"); loc }
    [ typ ]
;;

let value_name_pattern ~loc type_name =
  ppat_var ~loc { txt = type_name ^ "_jsonschema"; loc }
;;

let create_value ~loc name value =
  [%stri let[@warning "-32-39"] [%p value_name_pattern ~loc name] = [%e value]]
;;

let schema_signature ~loc type_decl =
  let typ = schema_type ~loc (core_type_of_type_declaration type_decl) in
  let name = { txt = type_decl.ptype_name.txt ^ "_jsonschema"; loc } in
  psig_value ~loc (value_description ~loc ~name ~type_:typ ~prim:[])
;;

let create_typed_value ~loc type_decl schema =
  let typ = schema_type ~loc (core_type_of_type_declaration type_decl) in
  if List.length type_decl.ptype_params = 0 then
    create_value ~loc type_decl.ptype_name.txt (pexp_constraint ~loc schema typ)
  else (
    let storage =
      [%stri
        let ppx_schema =
          Typed_endpoint.Json_schema.Deriver.polymorphic
            (Typed_endpoint.Json_schema.pack [%e schema])
        ;;]
    in
    let value =
      create_value
        ~loc
        type_decl.ptype_name.txt
        (pexp_constraint
           ~loc
           [%expr ppx_schema.Typed_endpoint.Json_schema.Deriver.schema]
           typ)
    in
    let module_ =
      pmod_constraint
        ~loc
        (pmod_structure ~loc [ storage; value ])
        (pmty_signature ~loc [ schema_signature ~loc type_decl ])
    in
    [%stri include [%m module_]])
;;

let rec schema_of_core_type ~(config : Attrs.config) ?(recursive_types = []) core_type =
  let loc = core_type.ptyp_loc in
  let schema, is_rec =
    match core_type with
    | [%type: int] | [%type: int32] | [%type: Int32.t] ->
      Schema.type_def ~loc "integer", false
    | [%type: int64] | [%type: Int64.t] | [%type: nativeint] | [%type: Nativeint.t] ->
      ( Schema.type_def
          ~loc
          (if Attrs.string_encoded core_type then
             "string"
           else
             "integer")
      , false )
    | [%type: float] -> Schema.type_def ~loc "number", false
    | [%type: string] | [%type: bytes] -> Schema.type_def ~loc "string", false
    | [%type: bool] -> Schema.type_def ~loc "boolean", false
    | [%type: char] ->
      ( Schema.type_def ~loc "string" |> Schema.string_lengths ~loc ~minimum:1 ~maximum:1
      , false )
    | [%type: unit] -> Schema.type_def ~loc "null", false
    | [%type: ([%t? ok], [%t? error]) result]
    | [%type: ([%t? ok], [%t? error]) Result.t]
    | [%type: ([%t? ok], [%t? error]) Stdlib.result] ->
      let error_schema, error_rec = schema_of_core_type ~config ~recursive_types error in
      let ok_schema, ok_rec = schema_of_core_type ~config ~recursive_types ok in
      Schema.result ~loc error_schema ok_schema, error_rec || ok_rec
    | [%type: [%t? t] option] ->
      let s, is_rec = schema_of_core_type ~config ~recursive_types t in
      Schema.nullable ~loc s, is_rec
    | [%type: [%t? t] ref] -> schema_of_core_type ~config ~recursive_types t
    | [%type: [%t? t] list] ->
      let t, is_rec = schema_of_core_type ~config ~recursive_types t in
      Schema.array ~loc t, is_rec
    | [%type: [%t? t] array] ->
      let t, is_rec = schema_of_core_type ~config ~recursive_types t in
      Schema.array ~loc t, is_rec
    | _ ->
      (match core_type.ptyp_desc with
       | Ptyp_var _ -> [%expr Typed_endpoint.Json_schema.Deriver.any], false
       | Ptyp_constr (id, _) ->
         (match id.txt with
          | Lident name when List.mem name recursive_types ->
            Schema.type_ref ~loc name, true
          | _ ->
            let schema = type_constr_conv ~loc id ~f:(fun s -> s ^ "_jsonschema") [] in
            ( [%expr
                Typed_endpoint.Json_schema.Deriver.with_id
                  [%e schema_id ~namespace:config.schema_namespace ~loc]
                  [%e schema]]
            , false ))
       | Ptyp_tuple types ->
         let results = List.map (schema_of_core_type ~config ~recursive_types) types in
         let ts = List.map fst results in
         let is_rec = List.exists snd results in
         Schema.tuple ~loc ts, is_rec
       | Ptyp_variant (row_fields, _, _) ->
         schema_of_poly_variant ~loc ~config ~recursive_types row_fields
       | _ ->
         let msg =
           Stdlib.Format.asprintf
             "typed-endpoint-ppx: unsupported type %a"
             Astlib.Pprintast.core_type
             core_type
         in
         [%expr [%ocaml.error [%e estring ~loc msg]]], false)
  in
  let schema =
    schema
    |> Schema.Annotation.add_description
         ~loc
         (Attrs.ct_description ~ocaml_doc:config.Attrs.ocaml_doc core_type)
    |> Schema.Annotation.add_title ~loc (Attrs.ct_title core_type)
    |> Schema.Annotation.add_format ~loc (Attrs.jsonschema_ct_format, core_type) core_type
    |> Schema.Annotation.add_maximum
         ~loc
         (Attrs.jsonschema_ct_maximum, core_type)
         core_type
    |> Schema.Annotation.add_minimum
         ~loc
         (Attrs.jsonschema_ct_minimum, core_type)
         core_type
    |> Schema.Annotation.add_annotations
         ~loc
         ~core_type
         (Attribute.get Attrs.jsonschema_ct_attrs core_type)
  in
  schema, is_rec

and schema_of_poly_variant
      ~loc
      ~(config : Attrs.config)
      ?(recursive_types = [])
      row_fields
  =
  let constrs, is_rec =
    List.fold_left
      (fun (constrs, is_rec) row_field ->
         let description_opt =
           Option.map
             (fun d -> d.txt)
             (Attrs.rtag_description ~ocaml_doc:config.Attrs.ocaml_doc row_field)
         in
         let title_opt =
           Option.map (fun title -> title.txt) (Attrs.rtag_title row_field)
         in
         match row_field.prf_desc with
         | Rtag (name, true, []) ->
           let name =
             match Attrs.rtag_name row_field with
             | Some name -> name.txt
             | None -> name.txt
           in
           `Tag (name, [], description_opt, title_opt) :: constrs, is_rec
         | Rtag (name, false, [ typ ]) ->
           let name =
             match Attrs.rtag_name row_field with
             | Some name -> name.txt
             | None -> name.txt
           in
           let raw_typs =
             match typ.ptyp_desc with
             | Ptyp_tuple tps -> tps
             | _ -> [ typ ]
           in
           let results =
             List.map (schema_of_core_type ~config ~recursive_types) raw_typs
           in
           let typs = List.map fst results in
           let typs_rec = List.exists snd results in
           `Tag (name, typs, description_opt, title_opt) :: constrs, is_rec || typs_rec
         | Rtag (_, true, [ _ ]) | Rtag (_, _, _ :: _ :: _) ->
           Location.raise_errorf ~loc "typed-endpoint-ppx: polymorphic_variant/Rtag/&"
         | Rinherit core_type ->
           let typ, typ_rec = schema_of_core_type ~config ~recursive_types core_type in
           `Inherit typ :: constrs, is_rec || typ_rec
         | Rtag (_, false, []) -> assert false)
      ([], false)
      row_fields
  in
  let constrs = List.rev constrs in
  let v = Schema.variants ~loc constrs in
  v, is_rec
;;

let schema_of_record
      ~loc
      ~(config : Attrs.config)
      ?(recursive_types = [])
      fields
      allow_extra_fields
  =
  let fields, required, is_rec =
    List.fold_left
      (fun (fields, required, is_rec) ({ pld_name; _ } as field) ->
         let name =
           match Attrs.ld_key field with
           | Some name -> name.txt
           | None -> pld_name.txt
         in
         let default = Attrs.ld_default field in
         let drop_required = Option.is_some default in
         let pld_type = Attrs.field_type field in
         let type_def, field_rec =
           schema_of_core_type ~config ~recursive_types pld_type
         in
         let type_def =
           type_def
           |> Schema.Annotation.add_description
                ~loc
                (Attrs.ld_description ~ocaml_doc:config.Attrs.ocaml_doc field)
           |> Schema.Annotation.add_title ~loc (Attrs.ld_title field)
           |> Schema.Annotation.add_format
                ~loc
                (Attrs.jsonschema_ld_format, field)
                pld_type
           |> Schema.Annotation.add_maximum
                ~loc
                (Attrs.jsonschema_ld_maximum, field)
                pld_type
           |> Schema.Annotation.add_minimum
                ~loc
                (Attrs.jsonschema_ld_minimum, field)
                pld_type
           |> Schema.Annotation.add_default ~loc default pld_type
           |> Schema.Annotation.add_annotations
                ~loc
                ~core_type:pld_type
                (Attribute.get Attrs.jsonschema_ld_attrs field)
         in
         ( [%expr [%e estring ~loc name], Typed_endpoint.Json_schema.pack [%e type_def]]
           :: fields
         , (if drop_required then
              required
            else
              { txt = name; loc } :: required)
         , is_rec || field_rec ))
      ([], [], false)
      fields
  in
  let fields = List.rev fields in
  let required = List.rev_map (fun { txt = name; _ } -> name) required in
  Schema.record ~loc ~properties:fields ~required ~allow_extra_fields, is_rec
;;

let schema_of_variants ~loc ~(config : Attrs.config) ?(recursive_types = []) variants =
  let variants, is_rec =
    List.fold_left
      (fun (variants, is_rec) ({ pcd_args; pcd_name = { txt = name; _ }; _ } as var) ->
         let name =
           match Attrs.cd_name var with
           | Some name -> name.txt
           | None -> name
         in
         let description_opt =
           Option.map
             (fun d -> d.txt)
             (Attrs.cd_description ~ocaml_doc:config.Attrs.ocaml_doc var)
         in
         let title_opt = Option.map (fun title -> title.txt) (Attrs.cd_title var) in
         match pcd_args with
         | Pcstr_record label_declarations ->
           let additional_properties =
             Attrs.resolve_additional_properties
               ~loc:var.pcd_loc
               ~strict:config.Attrs.strict
               ~decoder_strict:config.Attrs.decoder_strict
               ~allow:
                 (Option.is_some
                    (Attribute.get Attrs.jsonschema_cd_allow_extra_fields var))
               ~disallow:
                 (Option.is_some
                    (Attribute.get Attrs.jsonschema_cd_disallow_extra_fields var))
           in
           let obj_schema, obj_rec =
             schema_of_record
               ~loc
               ~config
               ~recursive_types
               label_declarations
               additional_properties
           in
           ( `Tag (name, [ obj_schema ], description_opt, title_opt) :: variants
           , is_rec || obj_rec )
         | Pcstr_tuple typs ->
           let results = List.map (schema_of_core_type ~config ~recursive_types) typs in
           let types = List.map fst results in
           let typs_rec = List.exists snd results in
           `Tag (name, types, description_opt, title_opt) :: variants, is_rec || typs_rec)
      ([], false)
      variants
  in
  let variants = List.rev variants in
  Schema.variants ~loc variants, is_rec
;;

let schema_of_type_decl ~loc ~(config : Attrs.config) ~recursive_types type_decl =
  let type_name = type_decl.ptype_name.txt in
  match type_decl.ptype_kind with
  | Ptype_variant variants ->
    let schema, is_rec = schema_of_variants ~loc ~config ~recursive_types variants in
    type_name, schema, is_rec
  | Ptype_record label_declarations ->
    let additional_properties =
      Attrs.resolve_additional_properties
        ~loc:type_decl.ptype_loc
        ~strict:config.Attrs.strict
        ~decoder_strict:config.Attrs.decoder_strict
        ~allow:
          (Option.is_some
             (Attribute.get Attrs.jsonschema_td_allow_extra_fields type_decl))
        ~disallow:
          (Option.is_some
             (Attribute.get Attrs.jsonschema_td_disallow_extra_fields type_decl))
    in
    let schema, is_rec =
      schema_of_record
        ~loc
        ~config
        ~recursive_types
        label_declarations
        additional_properties
    in
    type_name, schema, is_rec
  | Ptype_abstract ->
    (match type_decl.ptype_manifest with
     | Some core_type ->
       let schema, is_rec = schema_of_core_type ~config ~recursive_types core_type in
       type_name, schema, is_rec
     | None ->
       let msg = "typed-endpoint-ppx: abstract type without manifest" in
       type_name, [%expr [%ocaml.error [%e estring ~loc msg]]], false)
  | Ptype_open ->
    let msg = "typed-endpoint-ppx: open types not supported" in
    type_name, [%expr [%ocaml.error [%e estring ~loc msg]]], false
;;

let apply_defs ~loc = function
  | `Rec (primary, defs) ->
    let edv = evar ~loc "ppx_eds" in
    let vname name = "ppx_body_" ^ name in
    let pairs_expr =
      elist
        ~loc
        (List.map
           (fun (name, _) ->
              [%expr
                [%e estring ~loc name]
              , Typed_endpoint.Json_schema.pack [%e evar ~loc (vname name)]])
           defs)
    in
    let base_expr =
      [%expr
        Typed_endpoint.Json_schema.Deriver.root_ref
          ~root:[%e estring ~loc primary]
          ~definitions:([%e pairs_expr] @ ![%e edv])]
    in
    List.fold_right
      (fun (name, s) acc ->
         [%expr
           let [%p ppat_var ~loc { txt = vname name; loc }] = [%e s] in
           [%e acc]])
      defs
      base_expr
  | `NonRec schema ->
    let edv = evar ~loc "ppx_eds" in
    [%expr
      let ppx_result = [%e schema] in
      Typed_endpoint.Json_schema.Deriver.with_definitions ![%e edv] ppx_result]
;;

let str_type_decl ~ctxt ast removed_tuple_flag flag_ocaml_doc strict =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let config =
    Attrs.configure
      ~loc
      (snd ast)
      removed_tuple_flag
      flag_ocaml_doc
      strict
      (Code_path.fully_qualified_path (Expansion_context.Deriver.code_path ctxt))
  in
  let rec_flag, type_decls = ast in
  let type_decls = List.map name_type_params_in_td type_decls in
  match rec_flag, type_decls with
  | rec_flag, [ type_decl ] ->
    let type_name = type_decl.ptype_name.txt in
    let recursive_types =
      match rec_flag with
      | Recursive -> [ type_name ]
      | Nonrecursive -> []
    in
    let _, raw_schema, is_rec =
      schema_of_type_decl ~loc ~config ~recursive_types type_decl
    in
    let raw_schema =
      Schema.Annotation.type_declaration
        ~loc
        ~ocaml_doc:config.ocaml_doc
        type_decl
        raw_schema
    in
    let schema =
      if is_rec then
        [%expr
          let ppx_eds = ref [] in
          Typed_endpoint.Json_schema.Deriver.with_id
            [%e schema_id ~namespace:config.schema_namespace ~loc]
            [%e apply_defs ~loc (`Rec (type_name, [ type_name, raw_schema ]))]]
      else
        [%expr
          let ppx_eds = ref [] in
          [%e apply_defs ~loc (`NonRec raw_schema)]]
    in
    [ create_typed_value ~loc type_decl schema ]
  | rec_flag, type_decls when List.length type_decls > 1 ->
    let recursive_types =
      match rec_flag with
      | Recursive -> List.map (fun td -> td.ptype_name.txt) type_decls
      | Nonrecursive -> []
    in
    let raw_results =
      List.map
        (fun td ->
           let name, raw, is_rec = schema_of_type_decl ~loc ~config ~recursive_types td in
           let raw =
             Schema.Annotation.type_declaration
               ~loc:td.ptype_loc
               ~ocaml_doc:config.ocaml_doc
               td
               raw
           in
           name, raw, is_rec)
        type_decls
    in
    let any_recursive = List.exists (fun (_, _, is_rec) -> is_rec) raw_results in
    if any_recursive then
      List.map
        (fun (name, _, _) ->
           let td =
             List.find (fun td -> String.equal td.ptype_name.txt name) type_decls
           in
           let defs = List.map (fun (name, raw, _) -> name, raw) raw_results in
           let schema =
             [%expr
               let ppx_eds = ref [] in
               Typed_endpoint.Json_schema.Deriver.with_id
                 [%e schema_id ~namespace:config.schema_namespace ~loc:td.ptype_loc]
                 [%e apply_defs ~loc (`Rec (name, defs))]]
           in
           create_typed_value ~loc td schema)
        raw_results
    else
      List.map
        (fun (name, raw, _) ->
           let td =
             List.find (fun td -> String.equal td.ptype_name.txt name) type_decls
           in
           let schema =
             [%expr
               let ppx_eds = ref [] in
               [%e apply_defs ~loc (`NonRec raw)]]
           in
           create_typed_value ~loc td schema)
        raw_results
  | _, _ -> [%str [%ocaml.error "typed-endpoint-ppx: unsupported type"]]
;;

let sig_type_decl ~ctxt ast removed_tuple_flag flag_ocaml_doc strict =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let _config =
    Attrs.configure
      ~loc
      (snd ast)
      removed_tuple_flag
      flag_ocaml_doc
      strict
      (Code_path.fully_qualified_path (Expansion_context.Deriver.code_path ctxt))
  in
  match snd ast with
  | _ :: _ as type_decls ->
    List.map (fun td -> schema_signature ~loc (name_type_params_in_td td)) type_decls
  | [] ->
    let ext = Location.error_extensionf ~loc "typed-endpoint-ppx: unsupported type" in
    [ psig_extension ~loc ext [] ]
;;

let _ : Deriving.t =
  Deriving.add
    deriver_name
    ~str_type_decl:
      (Deriving.Generator.V2.make
         ~attributes:Attrs.attributes
         (Attrs.args ())
         str_type_decl)
    ~sig_type_decl:
      (Deriving.Generator.V2.make
         ~attributes:Attrs.attributes
         (Attrs.args ())
         sig_type_decl)
;;
