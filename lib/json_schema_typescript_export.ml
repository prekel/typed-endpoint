open! Base
open Result.Let_syntax

type node =
  { value : Yojson.Safe.t
  ; path : string list
  ; resource : string list
  }

type t =
  { nodes : node Map.M(String).t
  ; resources : string Map.M(String).t
  ; order : string list
  ; definitions : string list
  }

let escape segment =
  segment
  |> String.substr_replace_all ~pattern:"~" ~with_:"~0"
  |> String.substr_replace_all ~pattern:"/" ~with_:"~1"
;;

let pointer path =
  String.concat ~sep:"" (List.map path ~f:(fun part -> "/" ^ escape part))
;;

let error path message = Error ("TypeScript export at #" ^ pointer path ^ ": " ^ message)
let member fields name = List.Assoc.find fields name ~equal:String.equal

let maps =
  [ "properties"; "patternProperties"; "$defs"; "definitions"; "dependentSchemas" ]
;;

let lists = [ "allOf"; "anyOf"; "oneOf"; "prefixItems" ]

let values =
  [ "items"
  ; "additionalItems"
  ; "additionalProperties"
  ; "unevaluatedProperties"
  ; "unevaluatedItems"
  ; "contains"
  ; "propertyNames"
  ; "not"
  ; "if"
  ; "then"
  ; "else"
  ; "contentSchema"
  ]
;;

let index root =
  let rec visit state ~resource path value =
    match value with
    | (`Assoc _ | `Bool _) as value ->
      let fields =
        match value with
        | `Assoc fields -> fields
        | _ -> []
      in
      let%bind () =
        match
          List.find
            [ "$anchor"
            ; "$dynamicAnchor"
            ; "$dynamicRef"
            ; "$recursiveAnchor"
            ; "$recursiveRef"
            ]
            ~f:(fun name -> Option.is_some (member fields name))
        with
        | None -> Ok ()
        | Some name -> error path (name ^ " is not supported")
      in
      let%bind state, resource =
        match member fields "$id" with
        | None -> Ok (state, resource)
        | Some (`String id)
          when String.is_substring id ~substring:":"
               && not (String.is_substring id ~substring:"#") ->
          let%map resources =
            match Map.find state.resources id with
            | None -> Ok (Map.set state.resources ~key:id ~data:(pointer path))
            | Some previous ->
              if Yojson.Safe.equal (Map.find_exn state.nodes previous).value value then
                Ok state.resources
              else
                error path ("conflicting resource $id " ^ id)
          in
          { state with resources }, path
        | Some _ -> error path "$id must be an absolute URI without a fragment"
      in
      let key = pointer path in
      let state =
        { state with
          nodes = Map.set state.nodes ~key ~data:{ value; path; resource }
        ; order = key :: state.order
        }
      in
      List.fold_result fields ~init:state ~f:(fun state (name, child) ->
        let child_path = path @ [ name ] in
        if List.mem maps name ~equal:String.equal then (
          match
            child
          with
          | `Assoc children ->
            List.fold_result children ~init:state ~f:(fun state (key, value) ->
              let path = child_path @ [ key ] in
              let state =
                if String.equal name "$defs" || String.equal name "definitions" then
                  { state with definitions = pointer path :: state.definitions }
                else
                  state
              in
              visit state ~resource path value)
          | _ -> error child_path "expected a schema map")
        else if
          List.mem lists name ~equal:String.equal
          || (String.equal name "items"
              &&
              match child with
              | `List _ -> true
              | _ -> false)
        then (
          match
            child
          with
          | `List children ->
            List.fold_result
              (List.mapi children ~f:(fun i value -> i, value))
              ~init:state
              ~f:(fun state (i, value) ->
                visit state ~resource (child_path @ [ Int.to_string i ]) value)
          | _ -> error child_path "expected a schema array")
        else if List.mem values name ~equal:String.equal then
          visit state ~resource child_path child
        else
          Ok state)
    | _ -> error path "expected a schema object or boolean"
  in
  let%map state =
    visit
      { nodes = Map.empty (module String)
      ; resources = Map.empty (module String)
      ; order = []
      ; definitions = []
      }
      ~resource:[]
      []
      root
  in
  { state with order = List.rev state.order; definitions = List.rev state.definitions }
;;

let decode_fragment fragment =
  let buffer = Buffer.create (String.length fragment) in
  let hex c =
    match c with
    | '0' .. '9' -> Some (Char.to_int c - Char.to_int '0')
    | 'a' .. 'f' -> Some (10 + Char.to_int c - Char.to_int 'a')
    | 'A' .. 'F' -> Some (10 + Char.to_int c - Char.to_int 'A')
    | _ -> None
  in
  let rec loop i =
    if i = String.length fragment then
      Ok (Buffer.contents buffer)
    else if Char.equal fragment.[i] '%' then
      if i + 2 >= String.length fragment then
        Error "invalid percent escape in $ref"
      else (
        match
          hex fragment.[i + 1], hex fragment.[i + 2]
        with
        | Some high, Some low ->
          Buffer.add_char buffer (Char.of_int_exn ((16 * high) + low));
          loop (i + 3)
        | _ -> Error "invalid percent escape in $ref")
    else (
      Buffer.add_char buffer fragment.[i];
      loop (i + 1))
  in
  loop 0
;;

let resolve state node reference =
  let uri, fragment =
    match String.lsplit2 reference ~on:'#' with
    | Some (uri, fragment) -> uri, fragment
    | None -> reference, ""
  in
  let%bind resource =
    if String.is_empty uri then
      Ok node.resource
    else (
      match
        Map.find state.resources uri
      with
      | Some key -> Ok (Map.find_exn state.nodes key).path
      | None ->
        error
          node.path
          ("unresolved resource " ^ uri ^ " (external references are not fetched)"))
  in
  let%bind fragment =
    Result.map_error (decode_fragment fragment) ~f:(fun message ->
      "TypeScript export at #" ^ pointer node.path ^ ": " ^ message)
  in
  let%bind parts =
    if String.is_empty fragment then
      Ok []
    else if String.is_prefix fragment ~prefix:"/" then
      List.map
        (String.split (String.drop_prefix fragment 1) ~on:'/')
        ~f:(fun part ->
          part
          |> String.substr_replace_all ~pattern:"~1" ~with_:"/"
          |> String.substr_replace_all ~pattern:"~0" ~with_:"~")
      |> Result.return
    else
      error node.path ("unsupported $ref anchor #" ^ fragment)
  in
  let key = pointer (resource @ parts) in
  if Map.mem state.nodes key then
    Ok key
  else
    error node.path ("unresolved $ref " ^ reference)
;;

let bindings state =
  let%bind targets =
    List.fold_result state.order ~init:state.definitions ~f:(fun targets key ->
      let node = Map.find_exn state.nodes key in
      match node.value with
      | `Assoc fields ->
        (match member fields "$ref" with
         | None -> Ok targets
         | Some (`String reference) ->
           let%map target = resolve state node reference in
           targets @ [ target ]
         | Some _ -> error node.path "$ref must be a string")
      | _ -> Ok targets)
  in
  let _, names, order =
    List.fold
      targets
      ~init:(Set.empty (module String), Map.empty (module String), [])
      ~f:(fun (used, names, order) key ->
        if Map.mem names key then
          used, names, order
        else (
          let node = Map.find_exn state.nodes key in
          let base = Option.value (List.last node.path) ~default:"Root" in
          let base =
            String.map base ~f:(fun c ->
              if Char.is_alphanum c || Char.equal c '_' then
                c
              else
                '_')
          in
          let base =
            if String.is_empty base then
              "Schema"
            else
              base
          in
          let rec unique i =
            let name =
              if i = 1 then
                base
              else
                base ^ "_" ^ Int.to_string i
            in
            if Set.mem used name then
              unique (i + 1)
            else
              name
          in
          let name = unique 1 in
          Set.add used name, Map.set names ~key ~data:name, (key, name) :: order))
  in
  Ok (names, List.rev order)
;;

let schema root =
  let%bind state = index root in
  let%bind names, definitions = bindings state in
  let rec convert ~standalone path =
    let node = Map.find_exn state.nodes (pointer path) in
    match node.value with
    | `Bool true when standalone -> Ok (`Assoc [ "tsType", `String "unknown" ])
    | `Bool false when standalone ->
      Ok (`Assoc [ "not", `Assoc []; "tsType", `String "never" ])
    | `Bool value -> Ok (`Bool value)
    | `Assoc fields ->
      let prefix =
        match member fields "prefixItems" with
        | Some (`List []) -> None
        | prefix -> prefix
      in
      let%bind () =
        if Option.is_some prefix && Option.is_some (member fields "additionalItems") then
          error path "prefixItems and additionalItems cannot be combined"
        else if
          Option.is_some (member fields "unevaluatedItems")
          && (Option.is_none prefix
              || List.exists [ "$ref"; "allOf"; "anyOf"; "oneOf" ] ~f:(fun name ->
                Option.is_some (member fields name)))
        then
          error path "unevaluatedItems with schema applicators cannot be lowered safely"
        else
          Ok ()
      in
      let%map fields =
        List.fold_result fields ~init:[] ~f:(fun output (name, value) ->
          if
            List.mem [ "$id"; "$schema"; "$defs"; "definitions" ] name ~equal:String.equal
          then
            Ok output
          else if String.equal name "prefixItems" && Option.is_none prefix then
            Ok output
          else if
            String.equal name "unevaluatedItems" && Option.is_some (member fields "items")
          then
            Ok output
          else (
            let%map value =
              if String.equal name "$ref" then (
                match
                  value
                with
                | `String reference ->
                  let%map key = resolve state node reference in
                  `String ("#/definitions/" ^ Map.find_exn names key)
                | _ -> error path "$ref must be a string")
              else if List.mem maps name ~equal:String.equal then (
                match
                  value
                with
                | `Assoc children ->
                  let%map children =
                    List.map children ~f:(fun (key, _) ->
                      let%map value = convert ~standalone:false (path @ [ name; key ]) in
                      key, value)
                    |> Result.all
                  in
                  `Assoc children
                | _ -> error path "expected a schema map")
              else if
                List.mem lists name ~equal:String.equal
                || (String.equal name "items"
                    &&
                    match value with
                    | `List _ -> true
                    | _ -> false)
              then (
                match
                  value
                with
                | `List children ->
                  let%map children =
                    List.mapi children ~f:(fun i _ ->
                      convert ~standalone:false (path @ [ name; Int.to_string i ]))
                    |> Result.all
                  in
                  `List children
                | _ -> error path "expected a schema array")
              else if List.mem values name ~equal:String.equal then
                convert ~standalone:false (path @ [ name ])
              else
                Ok value
            in
            let name =
              if String.equal name "prefixItems" then
                "items"
              else if
                Option.is_some prefix
                && (String.equal name "items" || String.equal name "unevaluatedItems")
              then
                "additionalItems"
              else
                name
            in
            (name, value) :: output))
      in
      `Assoc (List.rev fields)
    | _ -> assert false
  in
  let%bind root = convert ~standalone:true [] in
  let%map definitions =
    List.map definitions ~f:(fun (key, name) ->
      let node = Map.find_exn state.nodes key in
      let%map value = convert ~standalone:true node.path in
      name, value)
    |> Result.all
  in
  if List.is_empty definitions then
    root
  else (
    match
      root
    with
    | `Assoc fields -> `Assoc (fields @ [ "definitions", `Assoc definitions ])
    | _ -> assert false)
;;
