open! Base
open Model

let pp = Stdlib.Format.fprintf
let pp_text = Stdlib.Format.pp_print_string

let pp_list ~sep print fmt values =
  Stdlib.Format.pp_print_list ~pp_sep:(fun fmt () -> pp fmt sep) print fmt values
;;

let pp_strings fmt values =
  pp fmt "@[<hov 1>[%a]@]" (pp_list ~sep:";@ " (fun fmt s -> pp fmt "%S" s)) values
;;

let pp_module ~signature fmt name body =
  pp
    fmt
    "@[<v 2>module %s %s@,%t@]@,end"
    name
    (if signature then
       ": sig"
     else
       "= struct")
    body
;;

let pp_type fmt (n : node) = pp fmt "%s.t" n.name
let pp_codec fmt (n : node) = pp fmt "%s.codec" n.name
let pp_dto_type fmt (n : node) = pp fmt "Dto.%a" pp_type n
let pp_schema fmt (n : node) = pp fmt "Dto.%s.t_jsonschema" n.name
let fn o = String.uncapitalize o.name
let errors_name o status = Stdlib.Printf.sprintf "%s_%d" (fn o) status

let constructors values =
  List.map values ~f:(fun value ->
    let base = module_name value in
    let name =
      if List.count values ~f:(fun other -> String.equal (module_name other) base) > 1
      then
        Stdlib.Printf.sprintf "%s__%s" base (String.prefix (digest value) 8)
      else
        base
    in
    value, name)
;;

let pp_known fmt props = pp_strings fmt (List.map props ~f:(fun (p : property) -> p.wire))

let pp_property_type fmt (p : property) =
  pp_type fmt p.node;
  if not p.required then
    pp
      fmt
      "%s"
      (match p.node.kind with
       | Nullable _ -> " Support.presence"
       | _ -> " option")
;;

let pp_declaration fmt (n : node) =
  match n.kind with
  | String -> pp fmt "string"
  | Integer -> pp fmt "int64"
  | Number -> pp fmt "float"
  | Bool -> pp fmt "bool"
  | Any -> pp fmt "Yojson.Safe.t"
  | Null -> pp fmt "unit"
  | Array item -> pp fmt "%a list" pp_type item
  | Nullable item -> pp fmt "%a option" pp_type item
  | Enum values ->
    pp_list ~sep:"@," (fun fmt (_, name) -> pp fmt "| %s" name) fmt (constructors values)
  | One_of (_, cases) ->
    pp_list
      ~sep:"@,"
      (fun fmt (tag, name) ->
         pp
           fmt
           "| %s of %a"
           name
           pp_type
           (List.Assoc.find_exn cases tag ~equal:String.equal))
      fmt
      (constructors (List.map cases ~f:fst))
  | Object ([], None) -> pp fmt "unit"
  | Object (props, extra) ->
    let field fmt (p : property) =
      pp fmt "%s : %a" p.field pp_property_type p;
      if not (String.equal p.field p.wire) then
        pp fmt " [@key %S]" p.wire
    in
    pp fmt "@[<hov 2>{ %a" (pp_list ~sep:";@ " field) props;
    Option.iter extra ~f:(fun n ->
      if not (List.is_empty props) then
        pp fmt ";@ ";
      pp fmt "additional_properties : (string * %a) list" pp_type n);
    pp fmt " }@]"
;;

let pp_codec_definition fmt (n : node) =
  match n.kind with
  | String -> pp fmt "Support.string"
  | Integer -> pp fmt "Support.int64"
  | Number -> pp fmt "Support.number"
  | Bool -> pp fmt "Support.bool"
  | Any -> pp fmt "Support.any"
  | Null -> pp fmt "Support.null"
  | Array item -> pp fmt "Support.list %a" pp_codec item
  | Nullable item -> pp fmt "Support.nullable %a" pp_codec item
  | Enum values ->
    let cases = constructors values in
    pp fmt "@[<v 2>{ Support.decode = (function@,";
    List.iter cases ~f:(fun (value, name) ->
      pp fmt "| `String %S -> Result.Ok %s@," value name);
    pp fmt "| _ -> Result.Error \"invalid enum\");@,encode = (function@,";
    pp_list
      ~sep:"@,"
      (fun fmt (value, name) -> pp fmt "| %s -> `String %S" name value)
      fmt
      cases;
    pp fmt ")@]@,}"
  | One_of (disc, cases) ->
    let constructors = constructors (List.map cases ~f:fst) in
    pp fmt "@[<v 2>{ Support.decode = (fun json ->@,";
    pp fmt "let open Result.Let_syntax in@,";
    pp fmt "let%%bind fields = Support.object_fields json in@,";
    pp fmt "match List.Assoc.find fields %S ~equal:String.equal with@," disc;
    List.iter constructors ~f:(fun (tag, name) ->
      let node = List.Assoc.find_exn cases tag ~equal:String.equal in
      pp
        fmt
        "| Some (`String %S) -> Result.map (%a.decode json) ~f:(fun x -> %s x)@,"
        tag
        pp_codec
        node
        name);
    pp fmt "| _ -> Result.Error \"unknown discriminator\");@,encode = (function@,";
    pp_list
      ~sep:"@,"
      (fun fmt (tag, name) ->
         let node = List.Assoc.find_exn cases tag ~equal:String.equal in
         pp fmt "| %s x -> %a.encode x" name pp_codec node)
      fmt
      constructors;
    pp fmt ")@]@,}"
  | Object (props, extra) ->
    pp fmt "@[<v 2>{ Support.decode = (fun json ->@,";
    pp fmt "let open Result.Let_syntax in@,";
    pp fmt "let%%bind fields = Support.object_fields json in@,";
    List.iteri props ~f:(fun i (p : property) ->
      let reader =
        if p.required then
          "required"
        else (
          match
            p.node.kind
          with
          | Nullable _ -> "presence"
          | _ -> "optional")
      in
      pp
        fmt
        "let%%bind v%d = Support.%s fields %S %a in@,"
        i
        reader
        p.wire
        pp_codec
        p.node);
    (match extra with
     | None -> pp fmt "let%%bind () = Support.closed fields %a in@," pp_known props
     | Some node ->
       pp
         fmt
         "let%%bind additional_properties = Support.extras fields %a %a in@,"
         pp_known
         props
         pp_codec
         node);
    (match props, extra with
     | [], None -> pp fmt "Ok ()"
     | _ ->
       pp fmt "@[<hov 2>Ok { ";
       pp_list
         ~sep:";@ "
         (fun fmt (i, (p : property)) -> pp fmt "%s = v%d" p.field i)
         fmt
         (List.mapi props ~f:(fun i p -> i, p));
       if Option.is_some extra then (
         if not (List.is_empty props) then
           pp fmt ";@ ";
         pp fmt "additional_properties");
       pp fmt " }@]");
    pp
      fmt
      ");@,encode = (fun %s ->@,"
      (if List.is_empty props && Option.is_none extra then
         "()"
       else
         "value");
    pp fmt "@[<hov 2>`Assoc (List.concat [";
    let field fmt (p : property) =
      let writer =
        if p.required then
          "field"
        else (
          match
            p.node.kind
          with
          | Nullable _ -> "presence_field"
          | _ -> "optional_field")
      in
      pp fmt "Support.%s %S %a value.%s" writer p.wire pp_codec p.node p.field
    in
    pp_list ~sep:";@ " field fmt props;
    Option.iter extra ~f:(fun node ->
      if not (List.is_empty props) then
        pp fmt ";@ ";
      pp
        fmt
        "Support.encode_extras %a %a value.additional_properties"
        pp_known
        props
        pp_codec
        node);
    pp fmt "]))@]@]@,}"
;;

let plain_scalar (n : node) =
  match n.kind with
  | String | Integer | Bool ->
    let kind =
      match n.kind with
      | String -> "string"
      | Integer -> "integer"
      | _ -> "boolean"
    in
    same n.schema (`Assoc [ "type", `String kind ])
  | Object (props, None) ->
    List.for_all props ~f:(fun p -> p.required)
    && (not (List.is_empty props))
    && List.for_all (fields n.schema) ~f:(fun (key, _) ->
      List.mem
        [ "type"; "properties"; "required"; "additionalProperties" ]
        key
        ~equal:String.equal)
  | _ -> false
;;

let pp_dto_ml normalize fmt (n : node) =
  pp_module ~signature:false fmt n.name (fun fmt ->
    let simple = plain_scalar n in
    pp fmt "@[<v>type t = %a" pp_declaration n;
    if simple then (
      (match n.kind with
       | Integer -> pp fmt " [@encoding `number]"
       | _ -> ());
      pp fmt " [@@@@deriving yojson, jsonschema]");
    pp fmt "@]@,@,";
    if simple then
      pp
        fmt
        "let t_jsonschema = Typed_endpoint.Json_schema.with_openapi ~schema_name:%S t_jsonschema@,@,"
        n.name
    else (
      pp
        fmt
        "(* Imported contract schema, tied to the generated OCaml representation. *)@,";
      pp fmt "let contract_schema : t Typed_endpoint.Json_schema.t =@,";
      pp
        fmt
        "  Typed_endpoint.Json_schema.Unsafe.of_yojson (Yojson.Safe.from_string %S)@,@,"
        (Yojson.Safe.to_string (canonical (normalize n.schema)));
      pp
        fmt
        "let t_jsonschema = Typed_endpoint.Json_schema.with_openapi ~schema_name:%S contract_schema@,@,"
        n.name);
    pp fmt "let codec : t Support.codec = %a" pp_codec_definition n;
    if not simple then
      pp fmt "@,@,let of_yojson = codec.decode@,let to_yojson = codec.encode")
;;

let pp_dto_mli fmt (n : node) =
  pp_module ~signature:true fmt n.name (fun fmt ->
    pp fmt "@[<v>type t = %a@]@,@," pp_declaration n;
    pp fmt "val codec : t Support.codec@,";
    pp fmt "include Typed_endpoint.Json_payload.S with type t := t")
;;

let pp_parameter_type fmt (p : parameter) =
  pp_dto_type fmt p.node;
  if not p.required then
    pp fmt " option"
;;

let pp_parameter_field fmt (p : parameter) = pp fmt "%s : %a" p.field pp_parameter_type p

let pp_response_type fmt r =
  let body fmt () =
    match r.node with
    | None -> pp fmt "unit"
    | Some node -> pp_dto_type fmt node
  in
  if List.is_empty r.headers then
    body fmt ()
  else
    pp
      fmt
      "@[<hov 2>{ body : %a;@ %a }@]"
      body
      ()
      (pp_list ~sep:";@ " pp_parameter_field)
      r.headers
;;

let pp_operation ~signature fmt o =
  pp_module ~signature fmt o.name (fun fmt ->
    pp_module ~signature fmt "Request" (fun fmt ->
      pp fmt "type t = ";
      if List.is_empty o.params && Option.is_none o.body then
        pp fmt "unit"
      else (
        pp fmt "@[<hov 2>{ %a" (pp_list ~sep:";@ " pp_parameter_field) o.params;
        Option.iter o.body ~f:(fun n ->
          if not (List.is_empty o.params) then
            pp fmt ";@ ";
          pp fmt "body : %a" pp_dto_type n);
        pp fmt " }@]"));
    pp fmt "@,@,";
    List.iter o.responses ~f:(fun r ->
      pp_module ~signature fmt (Stdlib.Printf.sprintf "Response_%d" r.status) (fun fmt ->
        pp fmt "type t = %a" pp_response_type r);
      pp fmt "@,@,");
    pp_module ~signature fmt "Response" (fun fmt ->
      pp fmt "@[<v>type t =@,";
      pp_list
        ~sep:"@,"
        (fun fmt r -> pp fmt "| Status_%d of Response_%d.t" r.status r.status)
        fmt
        o.responses;
      pp fmt "@]"))
;;

let pp_described_schema description fmt n =
  match description with
  | None -> pp_schema fmt n
  | Some description ->
    pp
      fmt
      "(Typed_endpoint.Json_schema.with_openapi ~description:%S %a)"
      description
      pp_schema
      n
;;

let pp_parameter_codec (p : parameter) fmt n =
  let string =
    match n.kind with
    | String | Enum _ -> true
    | _ -> false
  in
  let header = String.equal p.location "header" in
  pp
    fmt
    "@[<hov 2>%s.v ~schema:%a@ ~of_string:(Support.scalar Dto.%a ~string:%b)"
    (if header then
       "Header"
     else
       "Parameter")
    (pp_described_schema p.description)
    n
    pp_codec
    n
    string;
  if header then
    pp fmt "@ ~to_string:(Support.scalar_to_string Dto.%a)" pp_codec n;
  pp fmt " ()@]"
;;

let pp_header fmt (p : parameter) =
  pp
    fmt
    "@[<hov 2>Header.%s %S (%a)@]"
    (if p.required then
       "required"
     else
       "optional")
    p.wire
    (pp_parameter_codec p)
    p.node
;;

let pp_response_spec fmt r =
  let rec with_headers fmt = function
    | h :: rest ->
      pp fmt "@[<hov 2>Response.with_header (%a)@ (%a)@]" pp_header h with_headers rest
    | [] ->
      (match r.node with
       | None -> pp fmt "Response.empty ~description:%S ()" r.description
       | Some n ->
         pp fmt "@[<hov 2>Response.json ~description:%S@ (module struct@ " r.description;
         pp
           fmt
           "type t = %a@ let t_jsonschema = %a@ let to_yojson = Dto.%s.to_yojson@ end)@]"
           pp_dto_type
           n
           pp_schema
           n
           n.name)
  in
  with_headers fmt r.headers
;;

let pp_payload o r value fmt () =
  let rec tuple fmt = function
    | [] ->
      if List.is_empty r.headers then
        value fmt
      else
        pp fmt "%t.Operations.%s.Response_%d.body" value o.name r.status
    | h :: rest ->
      pp
        fmt
        "(%t.Operations.%s.Response_%d.%s, %a)"
        value
        o.name
        r.status
        h.field
        tuple
        rest
  in
  tuple fmt r.headers
;;

let pp_request fmt o =
  match o.body with
  | None -> pp fmt "Request.empty"
  | Some n ->
    let description =
      Option.bind (get o.metadata "requestBody") ~f:(fun body ->
        Option.map (get body "description") ~f:(string o.id))
    in
    pp fmt "@[<hov 2>Request.json (module struct@ type t = %a@ " pp_dto_type n;
    pp
      fmt
      "let t_jsonschema = %a@ let of_yojson = Dto.%s.of_yojson@ end)@]"
      (pp_described_schema description)
      n
      n.name
;;

let pp_decode_policy fmt o =
  let case fmt status =
    if List.mem o.errors status ~equal:Int.equal then (
      let response = List.find_exn o.responses ~f:(fun r -> r.status = status) in
      let value fmt =
        pp fmt "(decode_errors.Decode_errors.%s error)" (errors_name o status)
      in
      pp
        fmt
        "@[<hov 2>Decode_error_response.case ~response:(%a)@ ~map:(fun error -> %a)@]"
        pp_response_spec
        response
        (pp_payload o response value)
        ())
    else
      pp fmt "Decode_error_response.case ~response:(Response.empty ()) ~map:(fun _ -> ())"
  in
  if not (List.is_empty o.errors) then (
    pp fmt "@[<hov 2>@ ~decode_error:(Decode_error_response.by_status@ ";
    pp
      fmt
      "~bad_request:(%a)@ ~request_entity_too_large:(%a)@ ~unsupported_media_type:(%a))@]"
      case
      400
      case
      413
      case
      415)
;;

let pp_query fmt (p : parameter) =
  pp
    fmt
    "@ %s "
    (if p.required then
       "/!"
     else
       "/?");
  match p.node.kind with
  | Array item ->
    pp
      fmt
      "@[<hov 2>query_arg %S (Query.v ~encoding:`%s@ ~schema:%a@ "
      p.wire
      (if p.explode then
         "Repeated"
       else
         "Csv")
      (pp_described_schema p.description)
      p.node;
    pp
      fmt
      "~of_values:(fun values ->@ let module P = (val (%a)) in@ Result.all (List.map values ~f:P.of_string)) ())@]"
      (pp_parameter_codec p)
      item
  | _ -> pp fmt "arg %S (%a)" p.wire (pp_parameter_codec p) p.node
;;

let pp_handler_request fmt o =
  if List.is_empty o.params && Option.is_none o.body then
    pp fmt "()"
  else (
    pp
      fmt
      "@[<hov 2>Operations.%s.Request.{ %a"
      o.name
      (pp_list ~sep:";@ " (fun fmt (p : parameter) -> pp fmt "%s = %s" p.field p.field))
      o.params;
    if Option.is_some o.body then (
      if not (List.is_empty o.params) then
        pp fmt ";@ ";
      pp fmt "body");
    pp fmt " }@]")
;;

let pp_handler_call fmt o =
  pp
    fmt
    "@[<v>let%%bind result = handlers.Handlers.%s context %a in@,match result with@,"
    (fn o)
    pp_handler_request
    o;
  pp_list
    ~sep:"@,"
    (fun fmt r ->
       pp
         fmt
         "@[<hov 2>| Operations.%s.Response.Status_%d value ->@ respond r%d %a@]"
         o.name
         r.status
         r.status
         (pp_payload o r (fun fmt -> pp fmt "value"))
         ())
    fmt
    o.responses;
  pp fmt "@]"
;;

let pp_route fmt o =
  let path_parts =
    String.split o.path ~on:'/' |> List.filter ~f:(Fn.non String.is_empty)
  in
  let path_params =
    List.filter_map path_parts ~f:(fun segment ->
      if String.is_prefix segment ~prefix:"{" && String.is_suffix segment ~suffix:"}" then (
        let wire = String.sub segment ~pos:1 ~len:(String.length segment - 2) in
        match
          List.find o.params ~f:(fun p ->
            String.equal p.location "path" && String.equal p.wire wire)
        with
        | Some p -> Some p
        | None -> fail o.id "path" (Stdlib.Printf.sprintf "missing parameter %s" wire))
      else
        None)
  in
  if
    List.length path_params
    <> List.count o.params ~f:(fun p -> String.equal p.location "path")
  then
    fail o.id "path" "path parameters do not match template";
  let query = List.filter o.params ~f:(fun p -> String.equal p.location "query")
  and headers = List.filter o.params ~f:(fun p -> String.equal p.location "header") in
  pp fmt "@[<v 2>let route_%s =@,@[<hov 2>%s" (fn o) o.meth;
  List.iter path_parts ~f:(fun segment ->
    if String.is_prefix segment ~prefix:"{" then (
      let wire = String.sub segment ~pos:1 ~len:(String.length segment - 2) in
      let p = List.find_exn path_params ~f:(fun p -> String.equal p.wire wire) in
      pp fmt " /: arg %S (%a)" p.wire (pp_parameter_codec p) p.node)
    else
      pp fmt " / %S" segment);
  List.iter query ~f:(pp_query fmt);
  List.iter headers ~f:(fun p -> pp fmt "@ |> header (%a)" pp_header p);
  pp
    fmt
    "@]@,@[<hov 2>|> documented ~operation_id:%S@ ~description:%S"
    (str o.metadata "operationId" (ident o.name))
    (str o.metadata "description" "");
  Option.iter (get o.metadata "summary") ~f:(fun value ->
    pp fmt "@ ~summary:%S" (string o.id value));
  pp
    fmt
    "@ ~deprecated:%b@ ~tags:%a%a@]@,"
    (boolean o.metadata "deprecated" false)
    pp_strings
    (List.map
       (list (Option.value (get o.metadata "tags") ~default:(`List [])))
       ~f:(string o.id))
    pp_decode_policy
    o;
  pp fmt "@[<hov 2>|> accepts (%a)@]@," pp_request o;
  pp
    fmt
    "@[<hov 2>|> returns (%a)@]@,"
    (pp_list ~sep:"@ <|> " (fun fmt r ->
       pp fmt "case (`Code %d) (%a)" r.status pp_response_spec r))
    o.responses;
  let args =
    List.map (path_params @ query @ headers) ~f:(fun p -> p.field)
    @ List.map o.responses ~f:(fun r -> Stdlib.Printf.sprintf "r%d" r.status)
    @ [ "context"
      ; (if Option.is_some o.body then
           "body_handle"
         else
           "()")
      ]
  in
  pp fmt "@[<v 2>==> fun %a ->@," (pp_list ~sep:" " pp_text) args;
  if Option.is_some o.body then (
    pp fmt "let%%bind decoded = Request_body.read body_handle in@,match decoded with@,";
    pp fmt "| Error error -> Request_body.reject error@,| Ok body ->@,");
  pp_handler_call fmt o;
  pp fmt "@]@]@,in"
;;

let pp_config fmt root =
  let info = Option.value (get root "info") ~default:(`Assoc []) in
  let server fmt s =
    if Option.is_some (get s "variables") then
      fail "#/servers" "servers" "server variables are not supported";
    pp fmt "Typed_endpoint.Openapi.Server.v ~url:%S ()" (str s "url" "")
  in
  pp
    fmt
    "@[<hov 2>let openapi_config =@ Typed_endpoint.Openapi.Config.v ~title:%S@ ~version:%S@ ~description:%S@ ~servers:[%a] ()@]"
    (str info "title" "API")
    (str info "version" "1")
    (str info "description" "")
    (pp_list ~sep:";@ " server)
    (list (Option.value (get root "servers") ~default:(`List [])))
;;

let pp_group ~signature operations fmt group =
  let ops = List.filter operations ~f:(fun o -> String.equal o.group group) in
  pp_module ~signature fmt group (fun fmt ->
    if signature then
      pp fmt "val openapi_config : Typed_endpoint.Openapi.Config.t"
    else
      pp_config fmt (List.hd_exn ops).source_document;
    pp fmt "@,@,";
    pp_module ~signature fmt "Handlers" (fun fmt ->
      pp
        fmt
        "@[<hov 2>type 'context t = { %a }@]"
        (pp_list ~sep:";@ " (fun fmt o ->
           pp
             fmt
             "%s : 'context -> Operations.%s.Request.t -> Operations.%s.Response.t B.io"
             (fn o)
             o.name
             o.name))
        ops);
    pp fmt "@,@,";
    let hooks =
      List.concat_map ops ~f:(fun o -> List.map o.errors ~f:(fun status -> o, status))
    in
    pp_module ~signature fmt "Decode_errors" (fun fmt ->
      match hooks with
      | [] -> pp fmt "type t = unit"
      | _ ->
        pp
          fmt
          "@[<hov 2>type t = { %a }@]"
          (pp_list ~sep:";@ " (fun fmt (o, status) ->
             pp
               fmt
               "%s : Typed_endpoint.Decode_error.t -> Operations.%s.Response_%d.t"
               (errors_name o status)
               o.name
               status))
          hooks);
    pp fmt "@,@,";
    if signature then
      pp
        fmt
        "val groups : context:'context Endpoint.Context.t -> decode_errors:Decode_errors.t -> 'context Handlers.t -> Endpoint.Group.t list"
    else (
      pp
        fmt
        "@[<v 2>let groups ~context ~(decode_errors : Decode_errors.t) (handlers : 'context Handlers.t) =@,";
      if List.is_empty hooks then
        pp fmt "let _ = decode_errors in@,";
      pp_list ~sep:"@,@," pp_route fmt ops;
      pp
        fmt
        "@,@,@[<hov 2>[Group.make_with_context ~context [%a]]@]@]"
        (pp_list ~sep:";@ " (fun fmt o -> pp fmt "route_%s" (fn o)))
        ops))
;;

let pp_server ~signature root operations fmt () =
  let groups =
    List.dedup_and_sort
      (List.map operations ~f:(fun o -> o.group))
      ~compare:String.compare
  in
  pp fmt "@[<v>";
  if signature then
    pp fmt "val openapi_config : Typed_endpoint.Openapi.Config.t@,@,"
  else
    pp fmt "open! Typed_endpoint@,@,%a@,@," pp_config root;
  pp
    fmt
    "@[<v 2>module Make (B : Typed_endpoint.Backend.S) %s@,"
    (if signature then
       ": sig"
     else
       "= struct");
  if signature then
    pp fmt "module Endpoint : module type of Typed_endpoint.Make (B)@,@,"
  else
    pp
      fmt
      "module Endpoint = Typed_endpoint.Make (B)@,open! Endpoint@,open! B.Io.Let_syntax@,@,";
  pp_list ~sep:"@,@," (pp_group ~signature operations) fmt groups;
  pp fmt "@]@,end@]"
;;

let normalize nodes =
  let rec schema json =
    match json with
    | `Bool _ -> json
    | _ ->
      `Assoc
        (List.map (fields json) ~f:(fun (key, value) ->
           let value =
             if String.equal key "properties" then
               `Assoc
                 (List.map (fields value) ~f:(fun (name, value) -> name, schema value))
             else if List.mem [ "allOf"; "oneOf"; "anyOf" ] key ~equal:String.equal then
               `List (List.map (list value) ~f:schema)
             else if List.mem [ "items"; "additionalProperties" ] key ~equal:String.equal
             then
               schema value
             else if String.equal key "discriminator" then
               `Assoc
                 (List.map (fields value) ~f:(fun (key, value) ->
                    let value =
                      if String.equal key "mapping" then
                        `Assoc
                          (List.map (fields value) ~f:(fun (tag, target) ->
                             let id = string "#/discriminator" target in
                             match Hashtbl.find nodes id with
                             | Some (n : node) ->
                               ( tag
                               , `String
                                   (Stdlib.Printf.sprintf
                                      "#/components/schemas/%s"
                                      (escape n.name)) )
                             | None ->
                               fail
                                 "#/discriminator"
                                 "mapping"
                                 (Stdlib.Printf.sprintf
                                    "unknown discriminator target %s"
                                    id)))
                      else
                        value
                    in
                    key, value))
             else
               value
           in
           key, value))
  in
  schema
;;

let emit root nodes ordered operations =
  let file path print value : Generated_file.t =
    let contents =
      Stdlib.Format.asprintf
        "@[<v>(* Generated file. Do not edit. *)@,open! Base@,@,%a@]@."
        print
        value
      |> String.split ~on:'\n'
      |> List.map ~f:String.rstrip
      |> String.concat ~sep:"\n"
    in
    { path; contents }
  in
  [ file "support.ml" pp_text Support_source.ml
  ; file "support.mli" pp_text Support_source.mli
  ; file "dto.ml" (pp_list ~sep:"@,@," (pp_dto_ml (normalize nodes))) ordered
  ; file "dto.mli" (pp_list ~sep:"@,@," pp_dto_mli) ordered
  ; file "operations.ml" (pp_list ~sep:"@,@," (pp_operation ~signature:false)) operations
  ; file "operations.mli" (pp_list ~sep:"@,@," (pp_operation ~signature:true)) operations
  ; file "server.ml" (pp_server ~signature:false root operations) ()
  ; file "server.mli" (pp_server ~signature:true root operations) ()
  ]
;;
