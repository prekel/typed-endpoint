open Ppxlib
open! Base
open Ast_builder.Default
module List = Stdlib.List
module Option = Stdlib.Option
module String = Stdlib.String

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

let wrap_type_params ~loc params body =
  List.fold_right
    (fun param body ->
       let pattern = ppat_var ~loc { txt = param; loc } in
       let typ = schema_type ~loc (ptyp_var ~loc param) in
       let pattern = ppat_constraint ~loc pattern typ in
       [%expr fun [%p pattern] -> [%e body]])
    params
    body
;;

let create_typed_value ~loc type_decl params schema =
  let typ = core_type_of_type_declaration type_decl in
  let schema = pexp_constraint ~loc schema (schema_type ~loc typ) in
  let schema = wrap_type_params ~loc params schema in
  create_value ~loc type_decl.ptype_name.txt schema
;;

let rec schema_of_core_type
          ~(config : Attrs.config)
          ?(recursive_types = [])
          ?(compact_variants = false)
          core_type
  =
  let loc = core_type.ptyp_loc in
  let schema, is_rec =
    match core_type with
    | [%type: int] | [%type: int32] | [%type: nativeint] | [%type: int64] ->
      Schema.type_def ~loc "integer", false
    | [%type: float] -> Schema.type_def ~loc "number", false
    | [%type: string] | [%type: bytes] -> Schema.type_def ~loc "string", false
    | [%type: bool] -> Schema.type_def ~loc "boolean", false
    | [%type: char] ->
      ( Schema.type_def ~loc "string" |> Schema.string_lengths ~loc ~minimum:1 ~maximum:1
      , false )
    | [%type: unit] -> Schema.type_def ~loc "null", false
    | [%type: ([%t? error] * [%t? ok]) result] ->
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
       | Ptyp_var name -> evar ~loc name, false
       | Ptyp_constr (id, args) ->
         (match id.txt with
          | Lident name when List.mem name recursive_types ->
            Schema.type_ref ~loc name, true
          | _ ->
            let results = List.map (schema_of_core_type ~config ~recursive_types) args in
            let args = List.map fst results in
            let is_rec = List.exists snd results in
            let schema = type_constr_conv ~loc id ~f:(fun s -> s ^ "_jsonschema") args in
            (match is_rec with
             | true ->
               ( [%expr
                   let ppx_dependency_schema = [%e schema] in
                   let ppx_dependency_defs =
                     Typed_endpoint.Json_schema.Deriver.definitions ppx_dependency_schema
                   in
                   ppx_eds
                   := !ppx_eds
                      @ Stdlib.List.filter
                          (fun (name, _) -> not (Stdlib.List.mem_assoc name !ppx_eds))
                          ppx_dependency_defs;
                   Typed_endpoint.Json_schema.Deriver.without_definitions
                     ppx_dependency_schema]
               , is_rec )
             | false ->
               let unique_id =
                 estring
                   ~loc
                   (Printf.sprintf
                      "file://%s:%d"
                      loc.loc_start.pos_fname
                      loc.loc_start.pos_lnum)
               in
               ( [%expr
                   Typed_endpoint.Json_schema.Deriver.with_id [%e unique_id] [%e schema]]
               , is_rec )))
       | Ptyp_tuple types ->
         let results = List.map (schema_of_core_type ~config ~recursive_types) types in
         let ts = List.map fst results in
         let is_rec = List.exists snd results in
         Schema.tuple ~loc ts, is_rec
       | Ptyp_variant (row_fields, _, _) ->
         schema_of_poly_variant ~loc ~config ~recursive_types ~compact_variants row_fields
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
      ?(compact_variants = false)
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
             match config.Attrs.polymorphic_variant_tuple with
             | true -> [ typ ]
             | false ->
               (match typ.ptyp_desc with
                | Ptyp_tuple tps -> tps
                | _ -> [ typ ])
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
  let v = Schema.variants ~loc ~compact_variants constrs in
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
      (fun (fields, required, is_rec)
        ({ pld_name; pld_type; pld_loc = _loc; _ } as field) ->
         let name =
           match Attrs.ld_key field with
           | Some name -> name.txt
           | None -> pld_name.txt
         in
         let drop_required =
           Attribute.has_flag Attrs.jsonschema_option field
           || Attrs.ld_default field |> Option.is_some
         in
         let type_def, field_rec =
           match Attribute.get Attrs.jsonschema_ref field with
           | Some def -> Schema.type_ref ~loc def.txt, false
           | None ->
             (match pld_type with
              | [%type: [%t? inner] option] ->
                let s, r = schema_of_core_type ~config ~recursive_types inner in
                Schema.nullable ~loc s, r
              | _ -> schema_of_core_type ~config ~recursive_types pld_type)
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
           |> Schema.Annotation.add_default ~loc (Attrs.ld_default field) pld_type
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
  let required = List.map (fun { txt = name; _ } -> name) required in
  Schema.record ~loc ~properties:fields ~required ~allow_extra_fields, is_rec
;;

let resolve_additional_properties ~loc ~strict ~allow ~disallow =
  match allow, disallow with
  | true, true ->
    Location.raise_errorf
      ~loc
      "typed-endpoint-ppx: [@jsonschema.allow_extra_fields] and [@jsonschema.disallow_extra_fields] are mutually exclusive"
  | _, true -> false
  | _, false -> not strict
;;

let schema_of_variants
      ~loc
      ~(config : Attrs.config)
      ?(recursive_types = [])
      ?(compact_variants = false)
      variants
  =
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
             resolve_additional_properties
               ~loc:var.pcd_loc
               ~strict:config.Attrs.strict
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
  Schema.variants ~loc ~compact_variants variants, is_rec
;;

let schema_of_type_decl ~loc ~(config : Attrs.config) ~recursive_types type_decl =
  let type_name = type_decl.ptype_name.txt in
  let params = List.map (fun tp -> (get_type_param_name tp).txt) type_decl.ptype_params in
  match type_decl.ptype_kind with
  | Ptype_variant variants ->
    let compact_variants =
      Attribute.has_flag Attrs.jsonschema_td_compact_variants type_decl
    in
    let schema, is_rec =
      schema_of_variants ~loc ~config ~recursive_types ~compact_variants variants
    in
    type_name, schema, is_rec, params
  | Ptype_record label_declarations ->
    let additional_properties =
      resolve_additional_properties
        ~loc:type_decl.ptype_loc
        ~strict:config.Attrs.strict
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
    type_name, schema, is_rec, params
  | Ptype_abstract ->
    (match type_decl.ptype_manifest with
     | Some core_type ->
       let compact_variants =
         Attribute.has_flag Attrs.jsonschema_td_compact_variants type_decl
       in
       let schema, is_rec =
         schema_of_core_type ~config ~recursive_types ~compact_variants core_type
       in
       type_name, schema, is_rec, params
     | None ->
       let msg = "typed-endpoint-ppx: abstract type without manifest" in
       type_name, [%expr [%ocaml.error [%e estring ~loc msg]]], false, params)
  | Ptype_open ->
    let msg = "typed-endpoint-ppx: open types not supported" in
    type_name, [%expr [%ocaml.error [%e estring ~loc msg]]], false, params
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

let str_type_decl ~ctxt ast flag_polymorphic_variant_tuple flag_ocaml_doc strict =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let config : Attrs.config =
    { Attrs.polymorphic_variant_tuple = flag_polymorphic_variant_tuple
    ; Attrs.ocaml_doc = flag_ocaml_doc
    ; Attrs.strict = Option.value strict ~default:false
    }
  in
  match ast with
  | rec_flag, [ type_decl ] ->
    let type_name = type_decl.ptype_name.txt in
    let recursive_types =
      match rec_flag with
      | Recursive -> [ type_name ]
      | Nonrecursive -> []
    in
    let _, raw_schema, is_rec, params =
      schema_of_type_decl ~loc ~config ~recursive_types type_decl
    in
    let raw_schema =
      raw_schema
      |> Schema.Annotation.add_description
           ~loc
           (Attrs.td_description ~ocaml_doc:config.Attrs.ocaml_doc type_decl)
      |> Schema.Annotation.add_title ~loc (Attrs.td_title type_decl)
      |> Schema.Annotation.add_annotations
           ~loc
           (Attribute.get Attrs.jsonschema_td_attrs type_decl)
    in
    let raw_schema =
      Option.fold
        ~none:raw_schema
        ~some:(fun core_type ->
          Schema.Annotation.add_format
            ~loc
            (Attrs.jsonschema_td_format, type_decl)
            core_type
            raw_schema
          |> Schema.Annotation.add_maximum
               ~loc
               (Attrs.jsonschema_td_maximum, type_decl)
               core_type
          |> Schema.Annotation.add_minimum
               ~loc
               (Attrs.jsonschema_td_minimum, type_decl)
               core_type)
        type_decl.ptype_manifest
    in
    let schema =
      if is_rec then
        [%expr
          let ppx_eds = ref [] in
          [%e apply_defs ~loc (`Rec (type_name, [ type_name, raw_schema ]))]]
      else
        [%expr
          let ppx_eds = ref [] in
          [%e apply_defs ~loc (`NonRec raw_schema)]]
    in
    [ create_typed_value ~loc type_decl params schema ]
  | rec_flag, type_decls when List.length type_decls > 1 ->
    let recursive_types =
      match rec_flag with
      | Recursive -> List.map (fun td -> td.ptype_name.txt) type_decls
      | Nonrecursive -> []
    in
    let raw_results =
      List.map (schema_of_type_decl ~loc ~config ~recursive_types) type_decls
    in
    let any_recursive = List.exists (fun (_, _, is_rec, _) -> is_rec) raw_results in
    if any_recursive then
      List.map
        (fun (name, raw, _, params) ->
           let td =
             List.find (fun td -> String.equal td.ptype_name.txt name) type_decls
           in
           let raw =
             raw
             |> Schema.Annotation.add_description
                  ~loc
                  (Attrs.td_description ~ocaml_doc:config.Attrs.ocaml_doc td)
             |> Schema.Annotation.add_title ~loc (Attrs.td_title td)
             |> Schema.Annotation.add_annotations
                  ~loc
                  (Attribute.get Attrs.jsonschema_td_attrs td)
           in
           let raw =
             Option.fold
               ~none:raw
               ~some:(fun core_type ->
                 Schema.Annotation.add_format
                   ~loc
                   (Attrs.jsonschema_td_format, td)
                   core_type
                   raw
                 |> Schema.Annotation.add_maximum
                      ~loc
                      (Attrs.jsonschema_td_maximum, td)
                      core_type
                 |> Schema.Annotation.add_minimum
                      ~loc
                      (Attrs.jsonschema_td_minimum, td)
                      core_type)
               td.ptype_manifest
           in
           let defs =
             List.map
               (fun (n, r, _, _) ->
                  ( n
                  , if String.equal n name then
                      raw
                    else
                      r ))
               raw_results
           in
           let schema =
             [%expr
               let ppx_eds = ref [] in
               [%e apply_defs ~loc (`Rec (name, defs))]]
           in
           create_typed_value ~loc td params schema)
        raw_results
    else
      List.map
        (fun (name, raw, _, params) ->
           let td =
             List.find (fun td -> String.equal td.ptype_name.txt name) type_decls
           in
           let raw =
             raw
             |> Schema.Annotation.add_description
                  ~loc
                  (Attrs.td_description ~ocaml_doc:config.Attrs.ocaml_doc td)
             |> Schema.Annotation.add_title ~loc (Attrs.td_title td)
             |> Schema.Annotation.add_annotations
                  ~loc
                  (Attribute.get Attrs.jsonschema_td_attrs td)
           in
           let schema =
             [%expr
               let ppx_eds = ref [] in
               [%e apply_defs ~loc (`NonRec raw)]]
           in
           create_typed_value ~loc td params schema)
        raw_results
  | _, _ -> [%str [%ocaml.error "typed-endpoint-ppx: unsupported type"]]
;;

let sig_type_decl ~ctxt ast _flag_polymorphic_variant_tuple _flag_ocaml_doc _strict =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  match ast with
  | _, [ td ] ->
    let typ =
      combinator_type_of_type_declaration td ~f:(fun ~loc core_type ->
        schema_type ~loc core_type)
    in
    let name = { txt = td.ptype_name.txt ^ "_jsonschema"; loc } in
    [ psig_value ~loc (value_description ~loc ~name ~type_:typ ~prim:[]) ]
  | _, type_decls when List.length type_decls > 1 ->
    List.map
      (fun td ->
         let typ =
           combinator_type_of_type_declaration td ~f:(fun ~loc core_type ->
             schema_type ~loc core_type)
         in
         let name = { txt = td.ptype_name.txt ^ "_jsonschema"; loc } in
         psig_value ~loc (value_description ~loc ~name ~type_:typ ~prim:[]))
      type_decls
  | _, _ ->
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
