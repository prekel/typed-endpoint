open! Base

let member = Yojson.Safe.Util.member
let fields = Yojson.Safe.Util.to_assoc

(* jsonschema 0.1 resolves fragment references against the document root,
   including inside embedded $id resources. Reject that unsupported case rather
   than mistaking an unresolved reference for successful validation. *)
let unsupported_resource document schema =
  let rec visit seen ~root schema =
    match schema with
    | `Assoc values ->
      (List.Assoc.mem values "$id" ~equal:String.equal && not root)
      || List.exists values ~f:(fun (name, value) ->
        match name, value with
        | "$ref", `String reference
          when String.is_prefix reference ~prefix:"#/components/schemas/" ->
          if List.mem seen reference ~equal:String.equal then
            false
          else (
            let name = String.chop_prefix_exn reference ~prefix:"#/components/schemas/" in
            visit
              (reference :: seen)
              ~root:false
              (document |> member "components" |> member "schemas" |> member name))
        | ( ("properties" | "$defs" | "patternProperties" | "dependentSchemas")
          , `Assoc children ) ->
          List.exists children ~f:(fun (_, value) -> visit seen ~root:false value)
        | ("allOf" | "anyOf" | "oneOf" | "prefixItems"), `List children ->
          List.exists children ~f:(visit seen ~root:false)
        | ( ( "items"
            | "contains"
            | "additionalProperties"
            | "unevaluatedProperties"
            | "unevaluatedItems"
            | "propertyNames"
            | "not"
            | "if"
            | "then"
            | "else"
            | "contentSchema" )
          , value ) -> visit seen ~root:false value
        | _ -> false)
    | _ -> false
  in
  visit [] ~root:(Yojson.Safe.equal document schema) schema
;;

let validate ~document ~schema value =
  if unsupported_resource document schema then
    Error
      "test validator does not support embedded $id resources; validate the resource separately"
  else (
    let basic value = Yojson.Basic.from_string (Yojson.Safe.to_string value) in
    let root = `Assoc (("allOf", `List [ schema ]) :: fields document) in
    try
      match Jsonschema.create_validator_from_json ~schema:(basic root) () with
      | Error error ->
        Error (Stdlib.Format.asprintf "%a" Jsonschema.pp_compile_error error)
      | Ok validator ->
        Result.map_error
          (Jsonschema.validate validator (basic value))
          ~f:Jsonschema.Validation_error.to_string_verbose
    with
    | Yojson.Json_error error -> Error error)
;;

let resolve_response_exn document value =
  let rec resolve seen value =
    match member "$ref" value with
    | `String reference ->
      if List.mem seen reference ~equal:String.equal then
        Stdlib.failwith ("cyclic OpenAPI response reference: " ^ reference);
      let segments =
        String.chop_prefix_exn reference ~prefix:"#/components/responses/"
        |> String.split ~on:'/'
        |> List.map ~f:(fun segment ->
          String.substr_replace_all segment ~pattern:"~1" ~with_:"/"
          |> String.substr_replace_all ~pattern:"~0" ~with_:"~")
      in
      let target =
        List.fold
          segments
          ~init:(document |> member "components" |> member "responses")
          ~f:(fun json segment -> member segment json)
        |> resolve (reference :: seen)
      in
      (match List.Assoc.find (fields value) "description" ~equal:String.equal with
       | None -> target
       | Some description ->
         `Assoc
           (("description", description)
            :: List.filter (fields target) ~f:(fun (name, _) ->
              not (String.equal name "description"))))
    | _ -> value
  in
  resolve [] value
;;

let method_name : Typed_endpoint.Method.t -> string = function
  | `GET -> "get"
  | `POST -> "post"
  | `PUT -> "put"
  | `DELETE -> "delete"
  | `PATCH -> "patch"
  | `HEAD -> "head"
  | `OPTIONS -> "options"
  | `TRACE -> "trace"
  | `CONNECT -> "connect"
  | `Other name -> String.lowercase name
;;

let path_for_target_exn document ~meth ~target =
  let actual = Uri.path (Uri.of_string target) |> String.split ~on:'/' in
  let capture segment =
    String.is_prefix segment ~prefix:"{" && String.is_suffix segment ~suffix:"}"
  in
  document
  |> member "paths"
  |> fields
  |> List.filter_map ~f:(fun (path, item) ->
    let template = String.split path ~on:'/' in
    if
      (not (Poly.equal (member meth item) `Null))
      && List.equal
           (fun expected actual ->
              capture expected
              || String.equal (Uri.pct_decode expected) (Uri.pct_decode actual))
           template
           actual
    then
      Some (List.count template ~f:(fun segment -> not (capture segment)), path)
    else
      None)
  |> List.sort ~compare:(fun (a, _) (b, _) -> Int.compare b a)
  |> List.hd
  |> Option.value_map
       ~default:(Error ("no declared operation: " ^ meth ^ " " ^ target))
       ~f:(fun (_, path) -> Ok path)
  |> Result.ok_or_failwith
;;

let operation_exn document ~path ~meth =
  let item = document |> member "paths" |> member path in
  let operation = member meth item in
  if Poly.equal operation `Null then
    Stdlib.failwith ("no declared operation: " ^ meth ^ " " ^ path);
  let parameters json =
    match member "parameters" json with
    | `List values -> values
    | _ -> []
  in
  let own = parameters operation in
  let same left right =
    Poly.equal (member "name" left) (member "name" right)
    && Poly.equal (member "in" left) (member "in" right)
  in
  let inherited =
    List.filter (parameters item) ~f:(fun parameter ->
      not (List.exists own ~f:(same parameter)))
  in
  let effective =
    inherited @ own
    |> List.sort ~compare:(fun left right ->
      match
        String.compare
          (member "in" left |> Yojson.Safe.Util.to_string)
          (member "in" right |> Yojson.Safe.Util.to_string)
      with
      | 0 ->
        String.compare
          (member "name" left |> Yojson.Safe.Util.to_string)
          (member "name" right |> Yojson.Safe.Util.to_string)
      | comparison -> comparison)
  in
  let rest =
    List.filter (fields operation) ~f:(fun (name, _) ->
      not (String.equal name "parameters"))
  in
  `Assoc
    (if List.is_empty effective then
       rest
     else
       ("parameters", `List effective) :: rest)
;;

let operation document path meth = operation_exn document ~path ~meth
let header headers name = List.Assoc.find headers name ~equal:String.Caseless.equal

let media_type value =
  String.split value ~on:';' |> List.hd_exn |> String.strip |> String.lowercase
;;

let request_json_exn ~document ~path ~meth ~media_type value =
  let schema =
    operation document path meth
    |> member "requestBody"
    |> member "content"
    |> member media_type
    |> member "schema"
  in
  if Poly.equal schema `Null then
    Stdlib.failwith (meth ^ " " ^ path ^ ": undeclared request media type " ^ media_type);
  match validate ~document ~schema value with
  | Ok () -> ()
  | Error error -> Stdlib.failwith (meth ^ " " ^ path ^ ": request schema: " ^ error)
;;

let response_exn ~document ~path ~meth ~status ~headers ~body =
  let prefix = meth ^ " " ^ path ^ " -> " ^ Int.to_string status ^ ": " in
  let fail message = Stdlib.failwith (prefix ^ message) in
  let validate_value label schema value =
    match validate ~document ~schema value with
    | Ok () -> ()
    | Error error -> fail (label ^ ": " ^ error)
  in
  let response =
    operation document path meth |> member "responses" |> member (Int.to_string status)
  in
  if Poly.equal response `Null then
    fail "undeclared response status";
  let response = resolve_response_exn document response in
  (match member "headers" response with
   | `Assoc declared ->
     List.iter declared ~f:(fun (name, definition) ->
       match header headers name with
       | None ->
         if Poly.equal (member "required" definition) (`Bool true) then
           fail ("missing header " ^ name)
       | Some value ->
         let schema = member "schema" definition in
         (* Try primitive wire interpretations against the complete schema,
            including named references and unions, without flattening it. *)
         let candidates =
           [ Some (`String value)
           ; Result.try_with (fun () -> `Int (Int.of_string value)) |> Result.ok
           ; Result.try_with (fun () -> `Float (Float.of_string value)) |> Result.ok
           ; (match value with
              | "true" -> Some (`Bool true)
              | "false" -> Some (`Bool false)
              | _ -> None)
           ]
           |> List.filter_opt
         in
         if
           not
             (List.exists candidates ~f:(fun value ->
                Result.is_ok (validate ~document ~schema value)))
         then
           fail ("header " ^ name ^ ": no conforming primitive value"))
   | _ -> ());
  match member "content" response with
  | `Null | `Assoc [] ->
    if not (String.is_empty body) then
      fail "expected empty body";
    if Option.is_some (header headers "content-type") then
      fail "unexpected Content-Type on empty response"
  | `Assoc content ->
    let actual =
      match header headers "content-type" with
      | None -> fail "missing Content-Type"
      | Some value -> media_type value
    in
    let media =
      match List.Assoc.find content actual ~equal:String.equal with
      | None -> fail ("undeclared Content-Type " ^ actual)
      | Some media -> media
    in
    let value =
      if String.equal actual "application/json" then (
        try
          Yojson.Safe.from_string body
        with
        | Yojson.Json_error _ -> fail "invalid JSON body")
      else
        `String body
    in
    validate_value "body schema" (member "schema" media) value
  | _ -> fail "invalid response content declaration"
;;
