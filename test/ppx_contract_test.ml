open! Base

let write filename contents =
  let channel = Stdlib.open_out_bin filename in
  Exn.protect
    ~f:(fun () -> Stdlib.output_string channel contents)
    ~finally:(fun () -> Stdlib.close_out channel)
;;

let read filename =
  let channel = Stdlib.open_in_bin filename in
  Exn.protect
    ~f:(fun () -> Stdlib.really_input_string channel (Stdlib.in_channel_length channel))
    ~finally:(fun () -> Stdlib.close_in channel)
;;

let run ?(kind = "--impl") driver source output =
  let command =
    String.concat
      ~sep:" "
      (List.map [ driver; kind; source; "-o"; output ] ~f:Stdlib.Filename.quote)
  in
  Stdlib.Sys.command (command ^ " 2> " ^ Stdlib.Filename.quote (output ^ ".log"))
;;

let typecheck ~include_directory source output =
  let command =
    String.concat
      ~sep:" "
      (List.map
         [ "ocamlfind"
         ; "ocamlc"
         ; "-stop-after"
         ; "typing"
         ; "-package"
         ; "base,yojson,ppx_deriving_yojson.runtime"
         ; "-I"
         ; include_directory
         ; "-c"
         ; source
         ]
         ~f:Stdlib.Filename.quote)
  in
  Stdlib.Sys.command (command ^ " > " ^ Stdlib.Filename.quote output ^ " 2>&1")
;;

let () =
  let driver = Stdlib.Sys.argv.(1) in
  let include_directory = Stdlib.Filename.dirname Stdlib.Sys.argv.(2) in
  let directory = Stdlib.Filename.temp_file "typed-endpoint-ppx" "" in
  Stdlib.Sys.remove directory;
  Unix.mkdir directory 0o700;
  let first = directory ^ "/first" in
  let second = directory ^ "/second" in
  Unix.mkdir first 0o700;
  Unix.mkdir second 0o700;
  Exn.protect
    ~f:(fun () ->
      let fixture =
        {|
open! Base
module A = struct
  type 'a node = { value : 'a; next : 'a node option } [@@deriving jsonschema]
  type _ phantom = { count : int } [@@deriving jsonschema]
end
module B = struct
  type 'a node = { value : 'a; next : 'a node option } [@@deriving jsonschema]
  type _ phantom = { count : int } [@@deriving jsonschema]
end
|}
      in
      let expand folder =
        let source = folder ^ "/portable.ml" in
        let output = folder ^ "/expanded.ml" in
        write source fixture;
        assert (run driver source output = 0);
        read output
      in
      let a = expand first in
      let b = expand second in
      assert (String.equal a b);
      assert (not (String.is_substring a ~substring:directory));
      assert (not (String.is_substring a ~substring:"file://"));
      assert (String.is_substring a ~substring:"urn:typed-endpoint:schema:Portable.A");
      assert (String.is_substring a ~substring:"urn:typed-endpoint:schema:Portable.B");
      let bad_source = first ^ "/bad.ml" in
      let bad_output = first ^ "/bad_output.ml" in
      let reject ?(kind = "--impl") fixture diagnostic =
        write bad_source ("open! Base\n" ^ fixture);
        if run ~kind driver bad_source bad_output = 0 then
          Stdlib.failwith ("expected PPX rejection: " ^ fixture);
        let actual = read (bad_output ^ ".log") in
        if not (String.is_substring actual ~substring:diagnostic) then
          Stdlib.failwith ("unexpected PPX diagnostic for " ^ fixture ^ "\n" ^ actual)
      in
      List.iter
        [ ( {|type t = { value : int [@jsonschema.key "wire"] } [@@deriving jsonschema]|}
          , "[@jsonschema.key] has been removed; use [@key ...]" )
        ; ( {|type t = Value [@jsonschema.name "value"] [@@deriving jsonschema]|}
          , "[@jsonschema.name] has been removed; use [@name ...]" )
        ; ( {|type t = [ `Value [@jsonschema.name "value"] ] [@@deriving jsonschema]|}
          , "[@jsonschema.name] has been removed; use [@name ...]" )
        ; ( {|type t = { value : int [@jsonschema.default 0] } [@@deriving jsonschema]|}
          , "[@jsonschema.default] has been removed; use [@default ...]" )
        ; ( {|type t = { value : int option [@jsonschema.option] } [@@deriving jsonschema]|}
          , "[@jsonschema.option] has been removed; use [@default None]" )
        ; ( {|type t = { value : int option [@jsonschema.option] [@default None] } [@@deriving jsonschema]|}
          , "[@jsonschema.option] has been removed; use [@default None]" )
        ; ( {|type t = { value : int [@key "a"] [@key "b"] } [@@deriving jsonschema]|}
          , "Duplicated attribute" )
        ; ( {|type t = [ `Value [@yojson.name "a"] [@yojson.name "b"] ] [@@deriving jsonschema]|}
          , "Duplicated attribute" )
        ; ( {|type t = { value : (int [@default 1] [@default 2]) } [@@deriving jsonschema]|}
          , "Duplicated attribute" )
        ; ( {|type t = (int64 [@encoding `string] [@encoding `number]) [@@deriving jsonschema]|}
          , "Duplicated attribute" )
        ; {|type t = { value : int [@key 1] } [@@deriving jsonschema]|}, "Error"
        ; {|type t = Value [@name true] [@@deriving jsonschema]|}, "Error"
        ; {|type t = { value : int [@default] } [@@deriving jsonschema]|}, "Error"
        ; {|type t = (int64 [@encoding `invalid]) [@@deriving jsonschema]|}, "Error"
        ; {|type t = (int64 [@encoding "string"]) [@@deriving jsonschema]|}, "Error"
        ; ( {|type t = (int64 [@encoding `string] [@jsonschema.minimum 0]) [@@deriving jsonschema]|}
          , "numeric bounds cannot be applied to a string-encoded integer" )
        ; ( {|type t = { value : nativeint [@encoding `string] [@jsonschema.maximum 10] } [@@deriving jsonschema]|}
          , "numeric bounds cannot be applied to a string-encoded integer" )
        ; ( {|type t = { value : int64 [@encoding `string] [@jsonschema.attrs { minimum = 0 }] } [@@deriving jsonschema]|}
          , "numeric bounds cannot be applied to a string-encoded integer" )
        ; ( {|type t = string [@@jsonschema.format "date-time"] [@@deriving jsonschema]|}
          , "format expects a variant literal" )
        ; ( {|type t = { value : string [@jsonschema.attrs { format = "uuid" }] } [@@deriving jsonschema]|}
          , "format expects a variant literal" )
        ; ( {|type t = string [@@jsonschema.format (`Custom " ")] [@@deriving jsonschema]|}
          , "Custom format must not be empty" )
        ; ( {|type t = int [@@jsonschema.attrs { format = `Custom "" }] [@@deriving jsonschema]|}
          , "Custom format must not be empty" )
        ; ( {|type t = string [@@jsonschema.format (`Custom name)] [@@deriving jsonschema]|}
          , "with a string literal" )
        ; ( {|type t = string [@@jsonschema.format `Custom] [@@deriving jsonschema]|}
          , "with a string literal" )
        ; ( {|type t = string [@@jsonschema.format format] [@@deriving jsonschema]|}
          , "format expects a variant literal" )
        ; ( {|type t = bool [@@jsonschema.format `Uuid] [@@deriving jsonschema]|}
          , "format requires a primitive" )
        ; ( {|type scalar = string type t = scalar [@@jsonschema.format `Uuid] [@@deriving jsonschema]|}
          , "for custom types define <type>_jsonschema" )
        ; ( {|type t = { value : string [@jsonschema.title "x"] [@jsonschema.attrs { title = "x" }] } [@@deriving jsonschema]|}
          , "duplicate JSON Schema annotation 'title'" )
        ; ( {|type t = string [@@format (`Custom " ")] [@@deriving jsonschema]|}
          , "Custom format must not be empty" )
        ; ( {|type t = string [@@attrs { title = "x" }] [@@jsonschema.title "x"] [@@deriving jsonschema]|}
          , "duplicate JSON Schema annotation 'title'" )
        ; ( {|type t = string [@@format "uuid"] [@@deriving jsonschema]|}
          , "format expects a variant literal" )
        ; ( {|type t = string [@@jsonschema.attrs { format = `Uuid }] [@@jsonschema.format `Uuid] [@@deriving jsonschema]|}
          , "duplicate JSON Schema annotation 'format'" )
        ; ( {|type t = int [@@jsonschema.attrs { minimum = 0; minimum = 1 }] [@@deriving jsonschema]|}
          , "duplicate JSON Schema annotation 'minimum'" )
        ; ( {|type t = string [@@jsonschema.description "x"] [@@jsonschema.description "x"] [@@deriving jsonschema]|}
          , "duplicate JSON Schema annotation 'description'" )
        ; ( {|type t = string [@@jsonschema.attrs { title = "a" }] [@@jsonschema.attrs { description = "b" }] [@@deriving jsonschema]|}
          , "duplicate JSON Schema annotation 'attrs'" )
        ; ( {|type t = { value : string [@jsonschema.ref "External"] } [@@deriving jsonschema]|}
          , "[@jsonschema.ref] has been removed" )
        ; ( {|type t = Empty [@@jsonschema.compact_variants] [@@deriving jsonschema]|}
          , "variants always use Yojson arrays" )
        ; ( {|type t = [ `Value of int * string ] [@@deriving jsonschema { polymorphic_variant_tuple }]|}
          , "polymorphic_variant_tuple has been removed" )
        ; ( {|type t = { value : int } [@@deriving yojson, jsonschema { strict = false }]|}
          , "jsonschema strict = false conflicts with Yojson strict = true" )
        ; ( {|type t = { value : int } [@@deriving yojson { strict = false }, jsonschema { strict = true }]|}
          , "jsonschema strict = true conflicts with Yojson strict = false" )
        ; ( {|type t = { value : int } [@@deriving yojson, jsonschema] [@@jsonschema.allow_extra_fields]|}
          , "additionalProperties conflicts with Yojson strict = true" )
        ; ( {|type t = { value : int } [@@deriving of_yojson { strict = false }, jsonschema] [@@jsonschema.disallow_extra_fields]|}
          , "additionalProperties conflicts with Yojson strict = false" )
        ; ( {|type t = Value of { value : int } [@jsonschema.disallow_extra_fields] [@@deriving yojson { strict = false }, jsonschema]|}
          , "additionalProperties conflicts with Yojson strict = false" )
        ; ( {|type t = Value of { value : int } [@jsonschema.allow_extra_fields] [@@deriving yojson, jsonschema]|}
          , "additionalProperties conflicts with Yojson strict = true" )
        ; ( {|type t = { value : int } [@@jsonschema.allow_extra_fields] [@@jsonschema.disallow_extra_fields] [@@deriving jsonschema]|}
          , "are mutually exclusive" )
        ]
        ~f:(fun (fixture, diagnostic) -> reject fixture diagnostic);
      List.iter
        [ ( {|type t = string [@@jsonschema.format "uuid"] [@@deriving jsonschema]|}
          , "variant literal" )
        ; ( {|type t = { value : int [@jsonschema.ref "X"] } [@@deriving jsonschema]|}
          , "has been removed" )
        ; ( {|type t = { value : int } [@@deriving yojson, jsonschema { strict = false }]|}
          , "conflicts with Yojson" )
        ; ( {|type t = string [@@jsonschema.title "x"] [@@jsonschema.attrs { title = "x" }] [@@deriving jsonschema]|}
          , "duplicate JSON Schema annotation" )
        ]
        ~f:(fun (fixture, diagnostic) -> reject ~kind:"--intf" fixture diagnostic);
      let compile fixture =
        write bad_source ("open! Base\n" ^ fixture);
        if run driver bad_source bad_output <> 0 then
          Stdlib.failwith ("unexpected expansion failure: " ^ read (bad_output ^ ".log"));
        typecheck ~include_directory bad_output (bad_output ^ ".log")
      in
      let good_formats =
        {|type t = { date : string [@jsonschema.format `Date_time];
                     integer : int [@jsonschema.attrs { format = `Int32 }];
                     number : float [@jsonschema.format `Double];
                     custom : string option [@jsonschema.format (`Custom "my-format")] }
          [@@deriving jsonschema]|}
      in
      if compile good_formats <> 0 then
        Stdlib.failwith ("valid formats failed typing: " ^ read (bad_output ^ ".log"));
      List.iter
        [ {|type _ t = { value : int } [@@deriving jsonschema]
            type other = { value : int }
            let _ : other Typed_endpoint.Json_schema.t = t_jsonschema|}
        ; {|type (_, 'a, _) t = { value : 'a } [@@deriving jsonschema]
            let _ : int Typed_endpoint.Json_schema.t = t_jsonschema|}
        ]
        ~f:(fun fixture ->
          if compile fixture = 0 then
            Stdlib.failwith ("expected schema constant type rejection: " ^ fixture);
          let actual = read (bad_output ^ ".log") in
          assert (String.is_substring actual ~substring:"not compatible"));
      List.iter
        [ {|type t = string [@@jsonschema.format `Date_tiem] [@@deriving jsonschema]|}
        ; {|type t = string [@@jsonschema.format `Int64] [@@deriving jsonschema]|}
        ; {|type t = int [@@jsonschema.attrs { format = `Uuid }] [@@deriving jsonschema]|}
        ; {|type t = float option [@@jsonschema.format `Int32] [@@deriving jsonschema]|}
        ; {|type t = (int64 [@encoding `string]) [@@jsonschema.format `Int64] [@@deriving jsonschema]|}
        ]
        ~f:(fun fixture ->
          if compile fixture = 0 then
            Stdlib.failwith ("expected type rejection: " ^ fixture);
          let actual = read (bad_output ^ ".log") in
          assert (String.is_substring actual ~substring:"format");
          assert (String.is_substring actual ~substring:"does not allow tag"));
      List.iter
        [ {|module Payload = struct
              type t = int [@@deriving jsonschema]
              let of_yojson _ = Ok 0
              let t_jsonschema =
                Typed_endpoint.Json_schema.with_openapi ~schema_name:"Wrong"
                  (Typed_endpoint.Json_schema.string ())
            end
            let _ : (module Typed_endpoint.Request_payload.S with type t = int) =
              (module Payload)|}
        ; {|module Payload = struct
              type t = int [@@deriving jsonschema]
              let to_yojson value = `Int value
              let t_jsonschema =
                Typed_endpoint.Json_schema.with_openapi ~description:"Wrong"
                  (Typed_endpoint.Json_schema.string ())
            end
            let _ : (module Typed_endpoint.Response_payload.S with type t = int) =
              (module Payload)|}
        ]
        ~f:(fun fixture ->
          if compile fixture = 0 then
            Stdlib.failwith ("expected payload schema type rejection: " ^ fixture);
          let actual = read (bad_output ^ ".log") in
          assert (String.is_substring actual ~substring:"t_jsonschema");
          assert (String.is_substring actual ~substring:"not included"));
      write
        bad_source
        {|type t = { value : int [@jsonschema.key "wire"] } [@@deriving jsonschema]|};
      assert (run ~kind:"--intf" driver bad_source bad_output <> 0);
      assert (
        String.is_substring
          (read (bad_output ^ ".log"))
          ~substring:"[@jsonschema.key] has been removed");
      write
        bad_source
        {|
open! Base
type maybe_string = string option [@@deriving jsonschema]
type t = { value : maybe_string [@default None] } [@@deriving jsonschema]
|};
      assert (run driver bad_source bad_output = 0))
    ~finally:(fun () ->
      List.iter [ first; second ] ~f:(fun folder ->
        Stdlib.Sys.readdir folder
        |> Stdlib.Array.iter (fun name -> Stdlib.Sys.remove (folder ^ "/" ^ name));
        Unix.rmdir folder);
      Unix.rmdir directory)
;;
