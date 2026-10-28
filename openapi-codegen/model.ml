open! Base

module Diagnostic = struct
  type t =
    { path : string
    ; code : string
    ; message : string
    }

  let to_string t = Stdlib.Printf.sprintf "%s [%s]: %s" t.path t.code t.message
end

exception Invalid of Diagnostic.t

let fail path code message = raise (Invalid { path; code; message })

let escape x =
  x
  |> String.substr_replace_all ~pattern:"~" ~with_:"~0"
  |> String.substr_replace_all ~pattern:"/" ~with_:"~1"
;;

let child p x = Stdlib.Printf.sprintf "%s/%s" p (escape x)

let fields = function
  | `Assoc f -> f
  | _ -> []
;;

let get x k = List.Assoc.find (fields x) k ~equal:String.equal

let string p = function
  | `String s -> s
  | _ -> fail p "type" "expected string"
;;

let str x k default =
  match get x k with
  | None -> default
  | Some v -> string (child "#" k) v
;;

let boolean x k default =
  match get x k with
  | None -> default
  | Some (`Bool b) -> b
  | Some _ -> fail (child "#" k) "type" "expected boolean"
;;

let list = function
  | `List xs -> xs
  | _ -> []
;;

let sorted f = List.sort f ~compare:(fun (a, _) (b, _) -> String.compare a b)

let rec canonical = function
  | `Assoc f -> `Assoc (List.map (sorted f) ~f:(fun (k, v) -> k, canonical v))
  | `List xs -> `List (List.map xs ~f:canonical)
  | x -> x
;;

let same a b = Yojson.Safe.equal (canonical a) (canonical b)
let digest x = Stdlib.Digest.to_hex (Stdlib.Digest.string x)

let decode_token p s =
  let b = Buffer.create (String.length s) in
  let rec loop i =
    if i < String.length s then
      if Char.equal s.[i] '~' then (
        if i + 1 >= String.length s then
          fail p "selector" "invalid JSON Pointer escape";
        let c =
          match s.[i + 1] with
          | '0' -> '~'
          | '1' -> '/'
          | _ -> fail p "selector" "invalid JSON Pointer escape"
        in
        Buffer.add_char b c;
        loop (i + 2))
      else (
        Buffer.add_char b s.[i];
        loop (i + 1))
  in
  loop 0;
  Buffer.contents b
;;

let parts p value =
  if String.is_empty value then
    []
  else if String.is_prefix value ~prefix:"/" then
    List.map (String.split (String.drop_prefix value 1) ~on:'/') ~f:(decode_token p)
  else
    fail p "selector" "expected JSON Pointer"
;;

let select json path =
  List.fold (parts "#/config" path) ~init:(Some json) ~f:(fun value key ->
    Option.bind value ~f:(function
      | `Assoc f -> List.Assoc.find f key ~equal:String.equal
      | `List xs ->
        if
          not
            (String.equal key "0"
             || ((not (String.is_empty key))
                 && Char.is_digit key.[0]
                 && (not (Char.equal key.[0] '0'))
                 && String.for_all key ~f:Char.is_digit))
        then
          fail "#/config" "selector" "invalid array index";
        (match Int.of_string_opt key with
         | Some n when n >= 0 -> List.nth xs n
         | _ -> None)
      | _ -> None))
;;

let last_segment p text =
  let text =
    if String.is_prefix text ~prefix:"#" then
      String.drop_prefix text 1
    else
      text
  in
  (* URI fragment percent escapes are decoded before JSON Pointer tokens. *)
  let b = Buffer.create (String.length text) in
  let rec loop i =
    if i < String.length text then
      if Char.equal text.[i] '%' then (
        if i + 2 >= String.length text then
          fail p "transform" "invalid percent escape";
        let n =
          try Int.of_string ("0x" ^ String.sub text ~pos:(i + 1) ~len:2) with
          | _ -> fail p "transform" "invalid percent escape"
        in
        Buffer.add_char b (Char.of_int_exn n);
        loop (i + 3))
      else (
        Buffer.add_char b text.[i];
        loop (i + 1))
  in
  loop 0;
  match List.last (parts p (Buffer.contents b)) with
  | Some x when not (String.is_empty x) -> x
  | _ -> fail p "transform" "expected non-empty final segment"
;;

module Config = struct
  type selector =
    { select : string
    ; transform : string option
    }

  type t =
    { type_name : selector option
    ; schema_identity : selector option
    }

  let default = { type_name = None; schema_identity = None }

  let of_yojson json =
    try
      (match json with
       | `Assoc _ -> ()
       | _ -> fail "#/config" "config" "expected configuration object");
      List.iter (fields json) ~f:(fun (k, _) ->
        if not (String.equal k "naming") then
          fail (child "#/config" k) "config" "unknown configuration field");
      let naming = Option.value (get json "naming") ~default:(`Assoc []) in
      (match naming with
       | `Assoc _ -> ()
       | _ -> fail "#/config/naming" "config" "expected naming object");
      List.iter (fields naming) ~f:(fun (k, _) ->
        if not (List.mem [ "type_name"; "schema_identity" ] k ~equal:String.equal) then
          fail (child "#/config/naming" k) "config" "unknown naming field");
      let parse name =
        Option.map (get naming name) ~f:(fun x ->
          List.iter (fields x) ~f:(fun (k, _) ->
            if not (List.mem [ "select"; "transform" ] k ~equal:String.equal) then
              fail "#/config/naming" "config" "unknown selector field");
          let pointer =
            match get x "select" with
            | Some x -> string "#/config/naming" x
            | None -> fail "#/config/naming" "config" "missing select"
          in
          ignore (parts "#/config/naming" pointer : string list);
          let transform = Option.map (get x "transform") ~f:(string "#/config/naming") in
          Option.iter transform ~f:(fun x ->
            if not (String.equal x "json_pointer_last_segment") then
              fail "#/config/naming" "transform" "unknown transform");
          { select = pointer; transform })
      in
      Ok { type_name = parse "type_name"; schema_identity = parse "schema_identity" }
    with
    | Invalid e -> Error [ e ]
  ;;
end

module Source = struct
  type t =
    { name : string
    ; group : string option
    ; document : Yojson.Safe.t
    }
end

module Generated_file = struct
  type t =
    { path : string
    ; contents : string
    }
end

let extract selector p schema =
  Option.bind selector ~f:(fun (s : Config.selector) ->
    Option.map (select schema s.select) ~f:(fun value ->
      let value = string p value in
      if String.is_empty value then
        fail p "naming" "empty selected value";
      match s.transform with
      | None -> value
      | Some _ -> last_segment p value))
;;

let words text =
  let b = Buffer.create (String.length text * 2) in
  String.iteri text ~f:(fun i c ->
    if Char.is_alphanum c then (
      if Char.is_uppercase c && i > 0 && Char.is_lowercase text.[i - 1] then
        Buffer.add_char b '_';
      Buffer.add_char b (Char.lowercase c))
    else
      Buffer.add_char b '_');
  String.split (Buffer.contents b) ~on:'_' |> List.filter ~f:(Fn.non String.is_empty)
;;

let ident text =
  let name = String.concat ~sep:"_" (words text) in
  let name =
    if String.is_empty name then
      "value"
    else
      name
  in
  let name =
    if Char.is_digit name.[0] then
      "value_" ^ name
    else
      name
  in
  if
    List.mem
      [ "type"
      ; "module"
      ; "open"
      ; "let"
      ; "in"
      ; "match"
      ; "with"
      ; "and"
      ; "rec"
      ; "object"
      ; "method"
      ; "class"
      ; "val"
      ; "external"
      ; "include"
      ; "end"
      ; "begin"
      ; "fun"
      ; "function"
      ; "try"
      ; "exception"
      ; "if"
      ; "then"
      ; "else"
      ; "true"
      ; "false"
      ; "mutable"
      ; "private"
      ; "virtual"
      ; "inherit"
      ; "initializer"
      ; "constraint"
      ; "new"
      ; "as"
      ; "assert"
      ; "lazy"
      ; "of"
      ; "or"
      ; "to"
      ; "downto"
      ; "for"
      ; "while"
      ; "do"
      ; "done"
      ; "sig"
      ; "struct"
      ; "when"
      ; "nonrec"
      ]
      name
      ~equal:String.equal
  then
    name ^ "_"
  else
    name
;;

let module_name x = String.capitalize (ident x)

type node =
  { id : string
  ; base : string
  ; mutable name : string
  ; schema : Yojson.Safe.t
  ; kind : kind
  }

and kind =
  | String
  | Integer
  | Number
  | Bool
  | Any
  | Null
  | Enum of string list
  | Array of node
  | Nullable of node
  | Object of property list * node option
  | One_of of string * (string * node) list

and property =
  { wire : string
  ; field : string
  ; node : node
  ; required : bool
  }

type parameter =
  { wire : string
  ; location : string
  ; field : string
  ; node : node
  ; required : bool
  ; explode : bool
  ; description : string option
  }

type response =
  { status : int
  ; node : node option
  ; headers : parameter list
  ; description : string
  }

type operation =
  { path : string
  ; meth : string
  ; id : string
  ; mutable name : string
  ; group : string
  ; metadata : Yojson.Safe.t
  ; source_document : Yojson.Safe.t
  ; params : parameter list
  ; body : node option
  ; responses : response list
  ; errors : int list
  }

let schema_fields =
  [ "type"
  ; "format"
  ; "title"
  ; "description"
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
  ; "oneOf"
  ; "anyOf"
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
;;

let metadata_keys config =
  List.filter_map [ config.Config.type_name; config.schema_identity ] ~f:(fun selector ->
    Option.bind selector ~f:(fun x -> List.hd (parts "#/config" x.select)))
;;

let dialect p = function
  | `String
      ( "https://spec.openapis.org/oas/3.2/dialect/2026-02-26"
      | "https://json-schema.org/draft/2020-12/schema" ) -> ()
  | _ -> fail p "dialect" "unsupported JSON Schema dialect"
;;

let is_schema_field ~modern k =
  List.mem schema_fields k ~equal:String.equal
  || (modern
      && List.mem
           [ "const"; "examples"; "$schema"; "$id"; "$comment" ]
           k
           ~equal:String.equal)
;;

let rec clean ~modern config p json =
  match json with
  | `Assoc f ->
    if modern then (
      Option.iter (get json "$schema") ~f:(dialect (child p "$schema"));
      if Option.is_some (get json "nullable") then
        fail (child p "nullable") "schema" "use a null type union in OpenAPI 3.2.1";
      List.iter [ "exclusiveMinimum"; "exclusiveMaximum" ] ~f:(fun key ->
        match get json key with
        | None | Some (`Int _ | `Intlit _ | `Float _) -> ()
        | Some _ -> fail (child p key) "schema" "expected numeric exclusive bound"));
    `Assoc
      (List.filter_map f ~f:(fun (k, v) ->
         if
           List.mem (metadata_keys config) k ~equal:String.equal
           && not (is_schema_field ~modern k)
         then
           None
         else if List.mem [ "properties" ] k ~equal:String.equal then
           Some
             ( k
             , `Assoc
                 (List.map (fields v) ~f:(fun (name, v) ->
                    name, clean ~modern config (child (child p k) name) v)) )
         else if
           List.mem [ "items"; "additionalProperties" ] k ~equal:String.equal
           &&
           match v with
           | `Assoc _ -> true
           | _ -> false
         then
           Some (k, clean ~modern config (child p k) v)
         else if List.mem [ "allOf"; "oneOf"; "anyOf" ] k ~equal:String.equal then
           Some
             ( k
             , `List
                 (List.mapi (list v) ~f:(fun i v ->
                    clean ~modern config (child (child p k) (Int.to_string i)) v)) )
         else if not (is_schema_field ~modern k || String.is_prefix k ~prefix:"x-") then
           fail
             (child p k)
             "schema"
             (Stdlib.Printf.sprintf "unsupported schema keyword %s" k)
         else
           Some (k, v)))
  | `Bool true when modern -> `Assoc []
  | `Bool false when modern -> fail p "schema" "false schema has no generated value type"
  | _ -> fail p "schema" "expected schema object"
;;

(* Canonical schema dialect shared by DTO identity checks and export. *)
let rec json_schema json =
  match json with
  | `Bool _ -> json
  | _ ->
    let exclusive k =
      Yojson.Safe.equal (Option.value (get json k) ~default:`Null) (`Bool true)
    in
    let fs =
      List.filter_map (fields json) ~f:(fun (k, v) ->
        if
          String.equal k "nullable"
          || (String.equal k "minimum" && exclusive "exclusiveMinimum")
          || (String.equal k "maximum" && exclusive "exclusiveMaximum")
          || (List.mem [ "exclusiveMinimum"; "exclusiveMaximum" ] k ~equal:String.equal
              && Yojson.Safe.equal v (`Bool false))
        then
          None
        else (
          let v =
            if String.equal k "type" && boolean json "nullable" false then (
              match
                v
              with
              | `String t -> `List [ `String t; `String "null" ]
              | _ -> v)
            else if
              List.mem [ "exclusiveMinimum"; "exclusiveMaximum" ] k ~equal:String.equal
              && exclusive k
            then
              Option.value
                (get
                   json
                   (if String.equal k "exclusiveMinimum" then
                      "minimum"
                    else
                      "maximum"))
                ~default:v
            else if String.equal k "properties" then
              `Assoc (List.map (fields v) ~f:(fun (name, s) -> name, json_schema s))
            else if List.mem [ "oneOf"; "allOf"; "anyOf" ] k ~equal:String.equal then
              `List (List.map (list v) ~f:json_schema)
            else if List.mem [ "items"; "additionalProperties" ] k ~equal:String.equal
            then
              json_schema v
            else
              v
          in
          Some (k, v)))
    in
    `Assoc fs
;;
