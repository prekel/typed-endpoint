open! Base

module Spec_version = struct
  type t =
    | V3_0_3
    | V3_1_0
    | V3_2_1
end

module Export_error = struct
  type t =
    { path : string
    ; message : string
    }

  let to_string t = Stdlib.Printf.sprintf "%s: %s" t.path t.message
end

exception Unsupported of Export_error.t

let escape s =
  s
  |> String.substr_replace_all ~pattern:"~" ~with_:"~0"
  |> String.substr_replace_all ~pattern:"/" ~with_:"~1"
;;

let pointer p = String.concat ~sep:"/" ("#" :: List.map p ~f:escape)
let fail p message = raise (Unsupported { path = pointer p; message })

let fields = function
  | `Assoc f -> f
  | _ -> []
;;

let get f k = List.Assoc.find f k ~equal:String.equal

let remove f keys =
  List.filter f ~f:(fun (k, _) -> not (List.mem keys k ~equal:String.equal))
;;

let schema_maps = [ "properties"; "$defs"; "definitions" ]
let schema_lists = [ "allOf"; "anyOf"; "oneOf" ]
let schema_values = [ "items"; "additionalProperties"; "not" ]

let document ~spec_version root =
  match spec_version with
  | Spec_version.V3_2_1 ->
    Ok (`Assoc (("openapi", `String "3.2.1") :: remove (fields root) [ "openapi" ]))
  | Spec_version.V3_1_0 -> Ok root
  | V3_0_3 ->
    let errors = ref [] in
    let nodes = Hashtbl.create (module String) in
    let resources = Hashtbl.create (module String) in
    let definitions = ref [] in
    let rec index ~resource p json =
      let f = fields json in
      let resource =
        match get f "$id" with
        | Some (`String id) ->
          (match Hashtbl.find resources id with
           | Some previous when not (List.equal String.equal previous p) ->
             (* Repeated copies of one resource are legal if identical. *)
             let old, _ = Hashtbl.find_exn nodes (pointer previous) in
             if not (Yojson.Safe.equal old json) then
               fail p (Stdlib.Printf.sprintf "conflicting resource %s" id)
           | _ -> Hashtbl.set resources ~key:id ~data:p);
          p
        | _ -> resource
      in
      Hashtbl.set nodes ~key:(pointer p) ~data:(json, resource);
      List.iter f ~f:(fun (k, v) ->
        if List.mem schema_maps k ~equal:String.equal then
          List.iter (fields v) ~f:(fun (name, child) ->
            index ~resource (p @ [ k; name ]) child)
        else if List.mem schema_lists k ~equal:String.equal then (
          match
            v
          with
          | `List xs ->
            List.iteri xs ~f:(fun i x -> index ~resource (p @ [ k; Int.to_string i ]) x)
          | _ -> ())
        else if List.mem schema_values k ~equal:String.equal then
          index ~resource (p @ [ k ]) v)
    in
    let resolve p resource reference =
      let uri, fragment =
        match String.lsplit2 reference ~on:'#' with
        | Some pair -> pair
        | None -> reference, ""
      in
      let base =
        if String.is_empty uri then
          resource
        else (
          match
            Hashtbl.find resources uri
          with
          | Some p -> p
          | None -> fail p (Stdlib.Printf.sprintf "unresolved resource %s" uri))
      in
      let decode_fragment text =
        let b = Buffer.create (String.length text) in
        let rec loop i =
          if i < String.length text then
            if Char.equal text.[i] '%' then (
              if i + 2 >= String.length text then
                fail p "invalid reference escape";
              let digit c =
                match c with
                | '0' .. '9' -> Char.to_int c - Char.to_int '0'
                | 'a' .. 'f' -> 10 + Char.to_int c - Char.to_int 'a'
                | 'A' .. 'F' -> 10 + Char.to_int c - Char.to_int 'A'
                | _ -> fail p "invalid reference escape"
              in
              Buffer.add_char
                b
                (Char.of_int_exn ((16 * digit text.[i + 1]) + digit text.[i + 2]));
              loop (i + 3))
            else (
              Buffer.add_char b text.[i];
              loop (i + 1))
        in
        loop 0;
        Buffer.contents b
      in
      let fragment = decode_fragment fragment in
      if not (String.is_empty fragment || String.is_prefix fragment ~prefix:"/") then
        fail p "reference anchors are not supported";
      let parts =
        if String.is_empty fragment then
          []
        else
          String.split (String.drop_prefix fragment 1) ~on:'/'
          |> List.map ~f:(fun s ->
            s
            |> String.substr_replace_all ~pattern:"~1" ~with_:"/"
            |> String.substr_replace_all ~pattern:"~0" ~with_:"~")
      in
      let target = base @ parts in
      if not (Hashtbl.mem nodes (pointer target)) then
        fail p (Stdlib.Printf.sprintf "unresolved reference %s" reference);
      target
    in
    let component_name p =
      match p with
      | [ "components"; "schemas"; name ] -> name
      | _ ->
        let name = "Export_" ^ Stdlib.Digest.to_hex (Stdlib.Digest.string (pointer p)) in
        if Hashtbl.mem nodes (pointer [ "components"; "schemas"; name ]) then
          fail p "generated component name collides with an existing component";
        name
    in
    let reference target =
      let name = component_name target in
      if
        List.exists !definitions ~f:(fun (p, other) ->
          String.equal name other && not (List.equal String.equal p target))
      then
        fail target "generated component names collide";
      if
        not (List.exists !definitions ~f:(fun (p, _) -> List.equal String.equal p target))
      then
        definitions := (target, name) :: !definitions;
      `Assoc
        [ "$ref", `String (Stdlib.Printf.sprintf "#/components/schemas/%s" (escape name))
        ]
    in
    let allowed =
      [ "type"
      ; "title"
      ; "description"
      ; "format"
      ; "default"
      ; "example"
      ; "deprecated"
      ; "readOnly"
      ; "writeOnly"
      ; "nullable"
      ; "enum"
      ; "required"
      ; "properties"
      ; "items"
      ; "additionalProperties"
      ; "allOf"
      ; "anyOf"
      ; "oneOf"
      ; "not"
      ; "minimum"
      ; "maximum"
      ; "exclusiveMinimum"
      ; "exclusiveMaximum"
      ; "multipleOf"
      ; "minLength"
      ; "maxLength"
      ; "pattern"
      ; "minItems"
      ; "maxItems"
      ; "uniqueItems"
      ; "minProperties"
      ; "maxProperties"
      ; "discriminator"
      ; "xml"
      ; "externalDocs"
      ]
    in
    let rec convert seen p =
      if List.mem seen (pointer p) ~equal:String.equal then
        fail p "cyclic nullable reference";
      let json, resource = Hashtbl.find_exn nodes (pointer p) in
      match json with
      | `Bool true -> `Assoc []
      | `Bool false -> `Assoc [ "not", `Assoc [] ]
      | `Assoc original ->
        if Option.is_some (get original "nullable") then
          fail (p @ [ "nullable" ]) "nullable is not a JSON Schema 2020-12 constraint";
        let f =
          ref (remove original [ "$id"; "$schema"; "$defs"; "definitions"; "$comment" ])
        in
        let put k v = f := (k, v) :: remove !f [ k ] in
        let const_constraint =
          match get !f "const", get !f "enum" with
          | Some value, Some _ -> Some value
          | _ -> None
        in
        (match get !f "const" with
         | Some c ->
           (match get !f "enum" with
            | Some (`List _) -> f := remove !f [ "const" ]
            | Some _ -> fail (p @ [ "enum" ]) "expected enum array"
            | _ ->
              f := remove !f [ "const" ];
              put "enum" (`List [ c ]))
         | None -> ());
        List.iter
          [ "Minimum", "minimum"; "Maximum", "maximum" ]
          ~f:(fun (suffix, bound) ->
            let key = "exclusive" ^ suffix in
            match get !f key with
            | Some ((`Int _ | `Intlit _ | `Float _) as n) ->
              if Option.is_some (get !f bound) then
                fail
                  (p @ [ key ])
                  "combined inclusive and exclusive bounds require an explicit intersection";
              put bound n;
              put key (`Bool true)
            | _ -> ());
        (match get !f "type" with
         | Some (`String "null") ->
           (match get !f "enum" with
            | Some (`List xs) when not (List.mem xs `Null ~equal:Yojson.Safe.equal) ->
              f := [ "not", `Assoc [] ]
            | _ ->
              put "type" (`String "string");
              put "nullable" (`Bool true);
              put "enum" (`List [ `Null ]))
         | Some (`List xs) ->
           let non_null =
             List.filter xs ~f:(fun x -> not (Yojson.Safe.equal x (`String "null")))
           in
           (match non_null with
            | [ (`String _ as ty) ] when List.length xs = 2 ->
              put "type" ty;
              put "nullable" (`Bool true)
            | [ ty ] when List.length xs = 1 -> put "type" ty
            | _ -> fail (p @ [ "type" ]) "multiple non-null types cannot be exported")
         | _ -> ());
        (* Nullable references/compositions cannot be approximated by nullable
           next to a $ref: 3.0.3 ignores those siblings. *)
        List.iter !f ~f:(fun (k, _) ->
          if
            not
              (List.mem (allowed @ [ "$ref" ]) k ~equal:String.equal
               || String.is_prefix k ~prefix:"x-")
          then
            fail
              (p @ [ k ])
              (Stdlib.Printf.sprintf "unsupported OpenAPI 3.0.3 schema keyword %s" k));
        let output =
          List.map !f ~f:(fun (k, value) ->
            let value =
              if String.equal k "properties" then
                `Assoc
                  (List.map (fields value) ~f:(fun (name, _) ->
                     name, convert [] (p @ [ k; name ])))
              else if List.mem schema_lists k ~equal:String.equal then (
                match
                  value
                with
                | `List xs ->
                  `List
                    (List.mapi xs ~f:(fun i _ -> convert [] (p @ [ k; Int.to_string i ])))
                | _ -> fail (p @ [ k ]) "expected schema list")
              else if
                String.equal k "not" && not (Hashtbl.mem nodes (pointer (p @ [ k ])))
              then
                value
              else if List.mem schema_values k ~equal:String.equal then (
                match
                  k, value
                with
                | "additionalProperties", `Bool _ -> value
                | _ -> convert [] (p @ [ k ]))
              else
                value
            in
            k, value)
        in
        let converted =
          match get output "$ref" with
          | Some (`String r) ->
            let ref_schema = reference (resolve p resource r) in
            let siblings = remove output [ "$ref" ] in
            if List.is_empty siblings then
              ref_schema
            else
              `Assoc [ "allOf", `List [ ref_schema; `Assoc siblings ] ]
          | Some _ -> fail p "$ref must be a string"
          | None -> `Assoc output
        in
        (match const_constraint with
         | None -> converted
         | Some value ->
           (* Keep both constraints rather than comparing literals using OCaml
              equality: JSON object order and numeric representations differ. *)
           `Assoc [ "allOf", `List [ converted; `Assoc [ "enum", `List [ value ] ] ] ])
      | _ -> fail p "expected schema object"
    in
    let walk _path json ~schema_action =
      let map_object p f = function
        | `Assoc fs -> `Assoc (List.map fs ~f:(fun (k, v) -> k, f (p @ [ k ]) v))
        | x -> x
      in
      let map_field p key f = function
        | `Assoc fs ->
          `Assoc
            (List.map fs ~f:(fun (k, v) ->
               ( k
               , if String.equal k key then
                   f (p @ [ key ]) v
                 else
                   v )))
        | x -> x
      in
      let map_list p f = function
        | `List xs -> `List (List.mapi xs ~f:(fun i x -> f (p @ [ Int.to_string i ]) x))
        | x -> x
      in
      let content p json =
        map_object p (fun p media -> map_field p "schema" schema_action media) json
      in
      let parameter p json =
        json |> map_field p "schema" schema_action |> map_field p "content" content
      in
      let body p json = map_field p "content" content json in
      let response p json =
        json |> body p |> map_field p "headers" (fun p x -> map_object p parameter x)
      in
      let operation p json =
        json
        |> map_field p "parameters" (fun p x -> map_list p parameter x)
        |> map_field p "requestBody" body
        |> map_field p "responses" (fun p x -> map_object p response x)
      in
      let path_item p json =
        json |> map_field p "parameters" (fun p x -> map_list p parameter x)
        |> fun json ->
        List.fold
          [ "get"; "put"; "post"; "delete"; "patch"; "options"; "head"; "trace" ]
          ~init:json
          ~f:(fun json meth -> map_field p meth operation json)
      in
      json
      |> map_field [] "paths" (fun p x -> map_object p path_item x)
      |> map_field [] "components" (fun p x ->
        x
        |> map_field p "schemas" (fun p x -> map_object p schema_action x)
        |> map_field p "parameters" (fun p x -> map_object p parameter x)
        |> map_field p "headers" (fun p x -> map_object p parameter x)
        |> map_field p "requestBodies" (fun p x -> map_object p body x)
        |> map_field p "responses" (fun p x -> map_object p response x))
    in
    (try
       ignore
         (walk [] root ~schema_action:(fun p s ->
            index ~resource:[] p s;
            s)
          : Yojson.Safe.t);
       let convert_safe p s =
         try convert [] p with
         | Unsupported error ->
           errors := error :: !errors;
           s
       in
       let output = walk [] root ~schema_action:convert_safe in
       let rec gather done_ =
         let next =
           List.filter !definitions ~f:(fun (p, _) -> not (Set.mem done_ (pointer p)))
         in
         if List.is_empty next then
           []
         else (
           let done_ =
             List.fold next ~init:done_ ~f:(fun acc (p, _) -> Set.add acc (pointer p))
           in
           List.map next ~f:(fun (p, name) -> name, convert_safe p (`Assoc []))
           @ gather done_)
       in
       let existing =
         fields (Option.value (get (fields root) "components") ~default:(`Assoc []))
         |> fun f ->
         fields (Option.value (get f "schemas") ~default:(`Assoc []))
         |> List.map ~f:(fun (name, _) -> pointer [ "components"; "schemas"; name ])
         |> Set.of_list (module String)
       in
       let extra = gather existing in
       let root_fields = remove (fields output) [ "openapi" ] in
       let components =
         fields (Option.value (get root_fields "components") ~default:(`Assoc []))
       in
       let schemas =
         fields (Option.value (get components "schemas") ~default:(`Assoc []))
       in
       let extra =
         List.filter extra ~f:(fun (name, _) ->
           not (List.Assoc.mem schemas name ~equal:String.equal))
       in
       let output =
         `Assoc
           (("openapi", `String "3.0.3")
            ::
            (if List.is_empty extra then
               root_fields
             else
               ( "components"
               , `Assoc
                   (("schemas", `Assoc (schemas @ extra))
                    :: remove components [ "schemas" ]) )
               :: remove root_fields [ "components" ]))
       in
       if List.is_empty !errors then
         Ok output
       else
         Error (List.rev !errors)
     with
     | Unsupported error -> Error [ error ])
;;
