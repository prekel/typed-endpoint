open! Base
open Model

let generate_sources ?(config = Config.default) sources =
  try
    if List.is_empty sources then
      fail "#/sources" "source" "at least one source is required";
    let sources =
      List.sort sources ~compare:(fun (a : Source.t) b -> String.compare a.name b.name)
    in
    if
      List.contains_dup
        (List.map sources ~f:(fun (s : Source.t) -> s.name))
        ~compare:String.compare
    then
      fail "#/sources" "source" "source names must be unique";
    if
      List.length sources > 1
      && List.exists sources ~f:(fun s -> String.is_empty s.Source.name)
    then
      fail "#/sources" "source" "source names must not be empty";
    let nodes = Hashtbl.create (module String) in
    let ordered = ref [] in
    let process (source : Source.t) =
      let root = source.document in
      let scope =
        if String.is_empty source.name then
          ""
        else
          child "#/sources" source.name
      in
      let qualify p =
        if String.is_empty scope then
          p
        else
          scope ^ String.drop_prefix p 1
      in
      try
        let modern =
          match str root "openapi" "" with
          | "3.0.3" -> false
          | "3.2.1" -> true
          | _ -> fail "#/openapi" "version" "expected OpenAPI 3.0.3 or 3.2.1"
        in
        Option.iter (get root "jsonSchemaDialect") ~f:(fun value ->
          if not modern then
            fail "#/jsonSchemaDialect" "dialect" "requires OpenAPI 3.2.1";
          dialect "#/jsonSchemaDialect" value);
        if
          not
            (List.is_empty
               (fields (Option.value (get root "webhooks") ~default:(`Assoc []))))
        then
          fail "#/webhooks" "unsupported" "webhook generation is not supported";
        Option.iter source.group ~f:(fun group ->
          if String.is_empty group then
            fail "#/group" "group" "group name must not be empty");
        let fallback p base =
          match parts p (String.drop_prefix p 1) with
          | "paths" :: path :: meth :: rest ->
            let route =
              String.split path ~on:'/'
              |> List.filter ~f:(Fn.non String.is_empty)
              |> List.map ~f:(fun s ->
                if String.is_prefix s ~prefix:"{" then
                  "by_"
                  ^ String.strip s ~drop:(fun c -> Char.equal c '{' || Char.equal c '}')
                else
                  s)
            in
            let context =
              match rest with
              | "requestBody" :: "content" :: _ :: "schema" :: xs -> "request_body" :: xs
              | "responses" :: status :: "content" :: _ :: "schema" :: xs ->
                "response" :: status :: xs
              | _ -> [ base ]
            in
            String.concat
              ~sep:"_"
              ((meth :: route)
               @ List.filter context ~f:(fun x ->
                 not (List.mem [ "properties"; "schema" ] x ~equal:String.equal)))
          | _ -> base
        in
        let rec parse p base json =
          let id =
            Option.value (extract config.schema_identity p json) ~default:(qualify p)
          in
          let base =
            module_name
              (Option.value (extract config.type_name p json) ~default:(fallback p base))
          in
          let schema = json_schema (clean ~modern config p json) in
          match Hashtbl.find nodes id with
          | Some n ->
            if not (same n.schema schema) then
              fail
                p
                "identity"
                (Stdlib.Printf.sprintf "incompatible definitions for %s" id);
            n
          | None ->
            let declared_schema = schema in
            let schema =
              if modern then (
                match
                  json
                with
                | `Bool true -> `Assoc []
                | _ -> json)
              else
                json
            in
            let schema =
              if modern then (
                match
                  get schema "const"
                with
                | Some (`String value) ->
                  (match get schema "enum" with
                   | Some (`List xs)
                     when not (List.mem xs (`String value) ~equal:Yojson.Safe.equal) ->
                     fail p "const" "const and enum have no common value"
                   | _ -> ());
                  `Assoc
                    (("enum", `List [ `String value ])
                     :: List.filter (fields schema) ~f:(fun (k, _) ->
                       not (String.equal k "enum")))
                | Some `Null ->
                  (match get schema "type" with
                   | None | Some (`String "null") -> ()
                   | Some (`List xs)
                     when List.mem xs (`String "null") ~equal:Yojson.Safe.equal -> ()
                   | _ -> fail p "const" "const conflicts with type");
                  (match get schema "enum" with
                   | Some (`List xs) when not (List.mem xs `Null ~equal:Yojson.Safe.equal)
                     -> fail p "const" "const and enum have no common value"
                   | _ -> ());
                  `Assoc
                    (("type", `String "null")
                     :: List.filter (fields schema) ~f:(fun (k, _) ->
                       not (String.equal k "type")))
                | Some _ ->
                  fail
                    (child p "const")
                    "const"
                    "only string and null constants are supported"
                | None -> schema)
              else
                schema
            in
            let type_names =
              match get schema "type" with
              | Some (`List xs) when modern ->
                let names = List.map xs ~f:(string (child p "type")) in
                if List.is_empty names || List.contains_dup names ~compare:String.compare
                then
                  fail (child p "type") "type" "expected distinct nonempty types";
                if
                  List.length
                    (List.filter names ~f:(fun x -> not (String.equal x "null")))
                  > 1
                then
                  fail (child p "type") "type" "multiple non-null types are not supported";
                names
              | Some (`String t) -> [ t ]
              | _ -> []
            in
            let enum_null =
              match get schema "enum" with
              | Some (`List xs) -> List.mem xs `Null ~equal:Yojson.Safe.equal
              | _ -> true
            in
            if modern then (
              let allowed_type value =
                List.is_empty type_names || List.mem type_names value ~equal:String.equal
              in
              (match get schema "const" with
               | Some (`String _) when not (allowed_type "string") ->
                 fail p "const" "const conflicts with type"
               | Some `Null when not (allowed_type "null") ->
                 fail p "const" "const conflicts with type"
               | _ -> ());
              match get schema "enum" with
              | Some (`List xs)
                when List.exists xs ~f:(function
                       | `String _ -> true
                       | _ -> false)
                     && not (allowed_type "string") ->
                fail p "enum" "string enum conflicts with type"
              | Some (`List [ `Null ]) when not (allowed_type "null") ->
                fail p "enum" "null enum conflicts with type"
              | _ -> ());
            (* The input is finite and dereferenced; recursive references are rejected. *)
            List.iter [ "readOnly"; "writeOnly" ] ~f:(fun k ->
              if boolean schema k false then
                fail
                  (child p k)
                  "unsupported"
                  (Stdlib.Printf.sprintf "%s projections are not supported" k));
            let nested key suffix value =
              parse (child p key) (Stdlib.Printf.sprintf "%s_%s" base suffix) value
            in
            let nullable =
              (if modern then
                 (List.mem type_names "null" ~equal:String.equal
                  && List.length type_names = 2)
                 || (List.is_empty type_names
                     && enum_null
                     && Option.is_some (get schema "enum"))
               else
                 boolean schema "nullable" false && not (List.is_empty type_names))
              && enum_null
            in
            if
              nullable
              && List.exists [ "oneOf"; "allOf"; "anyOf"; "not" ] ~f:(fun k ->
                Option.is_some (get schema k))
            then
              fail
                p
                "nullable"
                "nullable compositions require a supported explicit null branch";
            let plain =
              `Assoc
                (List.filter_map (fields schema) ~f:(fun (k, v) ->
                   if
                     String.equal k "nullable"
                     || (List.mem (metadata_keys config) k ~equal:String.equal
                         && not (is_schema_field ~modern k))
                   then
                     None
                   else if modern && String.equal k "type" then (
                     match
                       List.filter type_names ~f:(fun x -> not (String.equal x "null"))
                     with
                     | [ t ] -> Some (k, `String t)
                     | _ -> Some (k, v))
                   else if nullable && String.equal k "enum" then
                     Some
                       ( k
                       , `List
                           (List.filter (list v) ~f:(fun x ->
                              not (Yojson.Safe.equal x `Null))) )
                   else
                     Some (k, v)))
            in
            if modern then (
              (match get schema "enum" with
               | Some (`List []) -> fail p "enum" "empty enum has no generated value type"
               | _ -> ());
              if
                List.equal String.equal type_names [ "null" ]
                && List.exists [ "oneOf"; "allOf"; "anyOf"; "not" ] ~f:(fun key ->
                  Option.is_some (get schema key))
              then
                fail p "composition" "unsupported null-only composition");
            let kind =
              if
                modern
                && (List.equal String.equal type_names [ "null" ]
                    || same
                         (Option.value (get schema "enum") ~default:`Null)
                         (`List [ `Null ]))
              then
                Null
              else if nullable then
                Nullable
                  (parse
                     (child p "nullable_value")
                     (Stdlib.Printf.sprintf "%s_value" base)
                     plain)
              else (
                match
                  get schema "oneOf"
                with
                | Some (`List branches) ->
                  let disc =
                    match get schema "discriminator" with
                    | Some d -> str d "propertyName" ""
                    | None -> ""
                  in
                  Option.iter (get schema "discriminator") ~f:(fun d ->
                    if Option.is_some (get d "defaultMapping") then
                      fail
                        (child p "discriminator")
                        "oneOf"
                        "defaultMapping is not supported");
                  if String.is_empty disc then
                    fail p "oneOf" "oneOf requires discriminator";
                  let cases =
                    List.mapi branches ~f:(fun i b ->
                      let n =
                        parse
                          (child (child p "oneOf") (Int.to_string i))
                          (Stdlib.Printf.sprintf "%s_case_%d" base i)
                          b
                      in
                      let props =
                        match n.kind with
                        | Object (ps, _) -> ps
                        | _ -> fail p "oneOf" "discriminator branch must be an object"
                      in
                      let tag =
                        match List.find props ~f:(fun x -> String.equal x.wire disc) with
                        | Some { required = true; node = { kind = Enum [ tag ]; _ }; _ }
                          -> tag
                        | _ ->
                          fail
                            p
                            "oneOf"
                            "discriminator must be required and have a singleton string enum"
                      in
                      tag, n)
                  in
                  if
                    List.is_empty cases
                    || List.contains_dup (List.map cases ~f:fst) ~compare:String.compare
                  then
                    fail p "oneOf" "discriminator tags must be distinct";
                  One_of (disc, cases)
                | Some _ -> fail p "oneOf" "expected branch array"
                | None ->
                  if
                    Option.is_some (get schema "anyOf")
                    || Option.is_some (get schema "not")
                  then
                    fail p "composition" "unsupported composition";
                  let schema =
                    if modern then
                      plain
                    else
                      schema
                  in
                  let schema =
                    match get schema "allOf" with
                    | None -> schema
                    | Some (`List branches) ->
                      let own =
                        `Assoc
                          (List.filter (fields schema) ~f:(fun (k, _) ->
                             not
                               (List.mem
                                  ("allOf" :: metadata_keys config)
                                  k
                                  ~equal:String.equal)))
                      in
                      let branches =
                        if List.is_empty (fields own) then
                          branches
                        else
                          own :: branches
                      in
                      if
                        not
                          (List.exists branches ~f:(fun branch ->
                             String.equal (str branch "type" "") "object"
                             || Option.is_some (get branch "properties")))
                      then
                        fail p "allOf" "allOf requires object branches";
                      let merged =
                        List.concat_map branches ~f:(fun x ->
                          fields (Option.value (get x "properties") ~default:(`Assoc [])))
                      in
                      let names =
                        List.dedup_and_sort
                          (List.map merged ~f:fst)
                          ~compare:String.compare
                      in
                      List.iter branches ~f:(fun b ->
                        if
                          (not (String.equal (str b "type" "object") "object"))
                          || List.exists
                               [ "allOf"; "oneOf"; "anyOf"; "not"; "enum"; "items" ]
                               ~f:(fun key -> Option.is_some (get b key))
                        then
                          fail p "allOf" "only flat object allOf is supported";
                        if
                          (not (boolean b "additionalProperties" true))
                          && List.exists names ~f:(fun n ->
                            not
                              (List.Assoc.mem
                                 (fields
                                    (Option.value
                                       (get b "properties")
                                       ~default:(`Assoc [])))
                                 n
                                 ~equal:String.equal))
                        then
                          fail
                            p
                            "allOf"
                            "closed branches forbid properties from other branches");
                      let props =
                        List.map names ~f:(fun name ->
                          let defs =
                            List.filter_map merged ~f:(fun (k, v) ->
                              if String.equal k name then
                                Some v
                              else
                                None)
                          in
                          let first = List.hd_exn defs in
                          if not (List.for_all defs ~f:(same first)) then
                            fail
                              p
                              "allOf"
                              (Stdlib.Printf.sprintf "incompatible property %s" name);
                          name, first)
                      in
                      let required =
                        List.concat_map branches ~f:(fun b ->
                          list (Option.value (get b "required") ~default:(`List [])))
                        |> List.dedup_and_sort ~compare:Poly.compare
                      in
                      `Assoc
                        [ "type", `String "object"
                        ; "properties", `Assoc props
                        ; "required", `List required
                        ; ( "additionalProperties"
                          , `Bool
                              (List.for_all branches ~f:(fun b ->
                                 boolean b "additionalProperties" true)) )
                        ]
                    | Some _ -> fail p "allOf" "expected branch array"
                  in
                  (match get schema "enum" with
                   | Some (`List xs)
                     when List.for_all xs ~f:(function
                            | `String _ -> true
                            | _ -> false)
                          && not (List.is_empty xs) ->
                     let xs = List.map xs ~f:(string p) in
                     if List.contains_dup xs ~compare:String.compare then
                       fail p "enum" "duplicate enum value";
                     Enum xs
                   | Some _ -> fail p "enum" "only nonempty string enums are supported"
                   | None ->
                     (match
                        str
                          schema
                          "type"
                          (if Option.is_some (get schema "properties") then
                             "object"
                           else
                             "any")
                      with
                      | "string" -> String
                      | "integer" -> Integer
                      | "number" -> Number
                      | "boolean" -> Bool
                      | "array" ->
                        let item =
                          match get schema "items" with
                          | Some x -> x
                          | None -> fail p "array" "missing items"
                        in
                        Array (nested "items" "item" item)
                      | "object" ->
                        let required =
                          List.map
                            (list
                               (Option.value (get schema "required") ~default:(`List [])))
                            ~f:(string p)
                        in
                        let props =
                          List.map
                            (sorted
                               (fields
                                  (Option.value
                                     (get schema "properties")
                                     ~default:(`Assoc []))))
                            ~f:(fun (wire, value) ->
                              { wire
                              ; field = ident wire
                              ; required = List.mem required wire ~equal:String.equal
                              ; node =
                                  parse
                                    (child (child p "properties") wire)
                                    (Stdlib.Printf.sprintf "%s_%s" base wire)
                                    value
                              })
                        in
                        let props =
                          List.map props ~f:(fun (prop : property) ->
                            if
                              List.count props ~f:(fun other ->
                                String.equal other.field prop.field)
                              > 1
                            then
                              { prop with
                                field =
                                  Stdlib.Printf.sprintf
                                    "%s__%s"
                                    prop.field
                                    (String.prefix (digest prop.wire) 8)
                              }
                            else
                              prop)
                        in
                        List.iter required ~f:(fun name ->
                          if
                            not (List.exists props ~f:(fun x -> String.equal x.wire name))
                          then
                            fail
                              p
                              "required"
                              (Stdlib.Printf.sprintf "unknown required property %s" name));
                        let extra =
                          match get schema "additionalProperties" with
                          | Some (`Bool false) -> None
                          | Some (`Assoc _ as x) ->
                            Some (nested "additionalProperties" "additional" x)
                          | None | Some (`Bool true) ->
                            Some (nested "additionalProperties" "additional" (`Assoc []))
                          | _ -> fail p "object" "invalid additionalProperties"
                        in
                        if
                          Option.is_some extra
                          && List.exists props ~f:(fun x ->
                            String.equal x.field "additional_properties")
                        then
                          fail p "field" "additional_properties is reserved";
                        Object (props, extra)
                      | "any"
                        when List.is_empty
                               (List.filter (fields schema) ~f:(fun (k, _) ->
                                  not
                                    (List.mem
                                       [ "$schema"
                                       ; "$id"
                                       ; "$comment"
                                       ; "title"
                                       ; "description"
                                       ; "examples"
                                       ]
                                       k
                                       ~equal:String.equal))) -> Any
                      | other ->
                        fail
                          p
                          "type"
                          (Stdlib.Printf.sprintf "unsupported schema type %s" other))))
            in
            let n = { id; base; name = base; schema = declared_schema; kind } in
            Hashtbl.set nodes ~key:id ~data:n;
            ordered := n :: !ordered;
            n
        in
        let parameter p json =
          let wire = str json "name" ""
          and location = str json "in" "" in
          if not (List.mem [ "path"; "query"; "header" ] location ~equal:String.equal)
          then
            fail p "parameter" "unsupported parameter location";
          let required = boolean json "required" false in
          if String.equal location "path" && not required then
            fail p "parameter" "path parameter must be required";
          let value =
            match get json "schema" with
            | Some x -> x
            | None -> fail p "parameter" "missing schema"
          in
          let node =
            parse (child p "schema") (Stdlib.Printf.sprintf "%s_%s" location wire) value
          in
          let scalar n =
            match n.kind with
            | String | Integer | Number | Bool | Enum _ -> true
            | _ -> false
          in
          (match node.kind with
           | Array item when String.equal location "query" && scalar item -> ()
           | _ when scalar node -> ()
           | _ -> fail p "parameter" "unsupported parameter representation");
          if
            String.equal location "query"
            && not (String.equal (str json "style" "form") "form")
          then
            fail p "parameter" "only form query serialization is supported";
          if
            String.equal location "header"
            && not (String.equal (str json "style" "simple") "simple")
          then
            fail p "parameter" "only simple header serialization is supported";
          if
            String.equal location "path"
            && not (String.equal (str json "style" "simple") "simple")
          then
            fail p "parameter" "only simple path serialization is supported";
          if boolean json "allowReserved" false then
            fail p "parameter" "allowReserved is not supported";
          { wire
          ; location
          ; field = ident (Stdlib.Printf.sprintf "%s_%s" location wire)
          ; node
          ; required
          ; explode = boolean json "explode" true
          ; description =
              Option.map (get json "description") ~f:(string (child p "description"))
          }
        in
        let content p json response =
          let media = fields (Option.value (get json "content") ~default:(`Assoc [])) in
          match media with
          | [] -> None
          | [ (media_type, body) ] when String.equal media_type "application/json" ->
            if Option.is_some (get body "itemSchema") then
              fail p "content" "streaming itemSchema is not supported";
            let schema =
              match get body "schema" with
              | Some x -> x
              | None -> fail p "content" "missing schema"
            in
            Some
              (parse
                 (child (child (child p "content") media_type) "schema")
                 (if response then
                    "response"
                  else
                    "request_body")
                 schema)
          | _ -> fail p "content" "v1 supports one application/json representation"
        in
        let paths = fields (Option.value (get root "paths") ~default:(`Assoc [])) in
        let operations =
          List.concat_map (sorted paths) ~f:(fun (path, item) ->
            let segments =
              String.split path ~on:'/' |> List.filter ~f:(Fn.non String.is_empty)
            in
            if
              (not (String.is_prefix path ~prefix:"/"))
              || ((not (String.equal path "/"))
                  && (String.is_suffix path ~suffix:"/"
                      || String.is_substring path ~substring:"//"))
            then
              fail (child "#/paths" path) "path" "expected canonical absolute path";
            List.iter segments ~f:(fun segment ->
              let has_brace =
                String.exists segment ~f:(fun c -> Char.equal c '{' || Char.equal c '}')
              in
              if
                has_brace
                && not
                     (String.length segment > 2
                      && String.is_prefix segment ~prefix:"{"
                      && String.is_suffix segment ~suffix:"}"
                      && not
                           (String.exists
                              (String.sub segment ~pos:1 ~len:(String.length segment - 2))
                              ~f:(fun c -> Char.equal c '{' || Char.equal c '}')))
              then
                fail
                  (child "#/paths" path)
                  "path"
                  "capture must occupy one complete segment");
            if Option.is_some (get item "servers") then
              fail (child "#/paths" path) "servers" "path-level servers are not supported";
            let group =
              Option.value
                source.group
                ~default:
                  (Option.value
                     (List.find segments ~f:(fun x ->
                        not (String.is_prefix x ~prefix:"{")))
                     ~default:"default")
            in
            List.filter_map
              (sorted (fields item))
              ~f:(fun (meth, meta) ->
                if
                  List.mem
                    [ "parameters"; "summary"; "description"; "servers" ]
                    meth
                    ~equal:String.equal
                  || String.is_prefix meth ~prefix:"x-"
                then
                  None
                else (
                  let p = child (child "#/paths" path) meth in
                  if
                    not
                      (List.mem
                         [ "get"; "post"; "put"; "patch"; "delete" ]
                         meth
                         ~equal:String.equal)
                  then
                    fail p "method" "unsupported HTTP method";
                  let security =
                    Option.value
                      (get meta "security")
                      ~default:(Option.value (get root "security") ~default:(`List []))
                  in
                  (match security with
                   | `List _ -> ()
                   | _ -> fail (child p "security") "security" "expected security array");
                  if
                    Option.is_some (get meta "servers")
                    || Option.is_some (get meta "callbacks")
                  then
                    fail
                      p
                      "unsupported"
                      "operation servers and callbacks are not supported";
                  if not (List.is_empty (list security)) then
                    fail p "security" "authorization generation is deferred";
                  let params =
                    List.mapi
                      (list (Option.value (get item "parameters") ~default:(`List [])))
                      ~f:(fun i x ->
                        parameter
                          (child
                             (child (child "#/paths" path) "parameters")
                             (Int.to_string i))
                          x)
                  in
                  let params =
                    List.fold
                      (List.mapi
                         (list (Option.value (get meta "parameters") ~default:(`List [])))
                         ~f:(fun i x -> i, x))
                      ~init:params
                      ~f:(fun acc (i, x) ->
                        let x =
                          parameter (child (child p "parameters") (Int.to_string i)) x
                        in
                        x
                        :: List.filter acc ~f:(fun y ->
                          not
                            (String.equal x.wire y.wire
                             && String.equal x.location y.location)))
                  in
                  let params =
                    List.sort params ~compare:(fun a b -> String.compare a.field b.field)
                  in
                  let body =
                    match get meta "requestBody" with
                    | None -> None
                    | Some json ->
                      if not (boolean json "required" false) then
                        fail
                          (child p "requestBody")
                          "body"
                          "optional request bodies are not supported";
                      (match content (child p "requestBody") json false with
                       | None ->
                         fail
                           (child p "requestBody")
                           "body"
                           "request body requires JSON content"
                       | Some n -> Some n)
                  in
                  let responses =
                    List.map
                      (sorted
                         (fields
                            (Option.value (get meta "responses") ~default:(`Assoc []))))
                      ~f:(fun (status, json) ->
                        let rp = child (child p "responses") status in
                        let status =
                          match Int.of_string_opt status with
                          | Some n
                            when String.length status = 3
                                 && String.for_all status ~f:Char.is_digit
                                 && n >= 200
                                 && n <= 599 -> n
                          | _ -> fail rp "response" "expected concrete final status"
                        in
                        let node = content rp json true in
                        let headers =
                          List.map
                            (sorted
                               (fields
                                  (Option.value (get json "headers") ~default:(`Assoc []))))
                            ~f:(fun (name, h) ->
                              parameter
                                (child (child rp "headers") name)
                                (`Assoc
                                    (("name", `String name)
                                     :: ("in", `String "header")
                                     :: fields h)))
                        in
                        { status; node; headers; description = str json "description" "" })
                  in
                  if List.is_empty responses then
                    fail p "response" "at least one response is required";
                  List.iter responses ~f:(fun r ->
                    if
                      List.mem [ 204; 205; 304 ] r.status ~equal:Int.equal
                      && Option.is_some r.node
                    then
                      fail p "response" "body-less status must not declare content");
                  let errors =
                    (if List.is_empty params && Option.is_none body then
                       []
                     else
                       [ 400 ])
                    @
                    if Option.is_some body then
                      [ 413; 415 ]
                    else
                      []
                  in
                  List.iter errors ~f:(fun status ->
                    if not (List.exists responses ~f:(fun r -> r.status = status)) then
                      fail
                        p
                        "decode_error"
                        (Stdlib.Printf.sprintf "missing reachable response %d" status));
                  let raw =
                    String.concat
                      ~sep:"_"
                      (String.uppercase meth
                       :: List.map segments ~f:(fun x ->
                         if String.is_prefix x ~prefix:"{" then
                           "by_"
                           ^ String.strip x ~drop:(fun c ->
                             Char.equal c '{' || Char.equal c '}')
                         else
                           x))
                  in
                  let name = module_name (str meta "operationId" raw) in
                  Some
                    { path
                    ; meth
                    ; id = qualify p
                    ; name
                    ; group
                    ; metadata = meta
                    ; source_document = root
                    ; params
                    ; body
                    ; responses
                    ; errors
                    })))
        in
        operations
      with
      | Invalid e ->
        if String.is_empty scope then
          raise (Invalid e)
        else
          raise (Invalid { e with path = scope ^ String.drop_prefix e.path 1 })
    in
    let operations = List.concat_map sources ~f:process in
    List.iter operations ~f:(fun o ->
      if
        List.count operations ~f:(fun other ->
          String.equal o.path other.path && String.equal o.meth other.meth)
        > 1
      then
        fail
          o.id
          "route"
          (Stdlib.Printf.sprintf "duplicate route %s %s" (String.uppercase o.meth) o.path));
    let explicit_ids =
      List.filter_map operations ~f:(fun o ->
        Option.map (get o.metadata "operationId") ~f:(fun value ->
          string o.id value, o.id))
    in
    List.iter explicit_ids ~f:(fun (id, path) ->
      if List.count explicit_ids ~f:(fun (other, _) -> String.equal id other) > 1 then
        fail path "operation_id" (Stdlib.Printf.sprintf "duplicate operationId %s" id));
    let dto_reserved =
      [ "Support"
      ; "Typed_endpoint"
      ; "Yojson"
      ; "Base"
      ; "Stdlib"
      ; "Result"
      ; "List"
      ; "String"
      ; "Option"
      ; "Int"
      ; "Int64"
      ; "Float"
      ; "Bool"
      ; "Let_syntax"
      ; "Ppx_deriving_yojson_runtime"
      ; "Ppx_deriving_runtime"
      ]
    in
    let group_reserved =
      [ "Endpoint"
      ; "B"
      ; "Dto"
      ; "Operations"
      ; "Support"
      ; "Typed_endpoint"
      ; "Parameter"
      ; "Header"
      ; "Query"
      ; "Response"
      ; "Request"
      ; "Request_body"
      ; "Group"
      ; "Decode_error_response"
      ; "Io"
      ; "Base"
      ; "Result"
      ; "List"
      ; "String"
      ; "Let_syntax"
      ]
    in
    let group_names =
      List.dedup_and_sort
        (List.map operations ~f:(fun o -> o.group))
        ~compare:String.compare
    in
    let operations =
      List.map operations ~f:(fun o ->
        let base = module_name o.group in
        let group =
          if
            List.count group_names ~f:(fun raw -> String.equal (module_name raw) base) > 1
            || List.mem group_reserved base ~equal:String.equal
          then
            Stdlib.Printf.sprintf "%s__%s" base (String.prefix (digest o.group) 8)
          else
            base
        in
        { o with group })
    in
    (* Renaming is computed from the complete graph, not traversal order. *)
    let rename ~reserved entries =
      List.iter entries ~f:(fun (base, id, set) ->
        if
          List.count entries ~f:(fun (b, _, _) -> String.equal base b) > 1
          || List.mem reserved base ~equal:String.equal
        then (
          let hash = digest id in
          let rec suffix length =
            let prefix = String.prefix hash length in
            if
              List.exists entries ~f:(fun (b, other, _) ->
                String.equal b base
                && (not (String.equal id other))
                && String.is_prefix (digest other) ~prefix)
            then
              if length = 32 then
                fail "#" "naming" "digest collision"
              else
                suffix (Int.min 32 (length + 4))
            else
              prefix
          in
          set (Stdlib.Printf.sprintf "%s__%s" base (suffix 8))))
    in
    rename
      ~reserved:dto_reserved
      (List.map !ordered ~f:(fun (n : node) -> n.base, n.id, fun s -> n.name <- s));
    rename
      ~reserved:[ "Dto" ]
      (List.map operations ~f:(fun o -> o.name, o.id, fun s -> o.name <- s));
    let output =
      Emitter.emit (List.hd_exn sources).document nodes (List.rev !ordered) operations
    in
    Ok output
  with
  | Invalid e -> Error [ e ]
;;

let generate ?config root =
  generate_sources ?config [ { Source.name = ""; group = None; document = root } ]
;;
