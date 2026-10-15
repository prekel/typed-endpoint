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

let () =
  let driver = Stdlib.Sys.argv.(1) in
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
end
module B = struct
  type 'a node = { value : 'a; next : 'a node option } [@@deriving jsonschema]
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
      let reject fixture diagnostic =
        write bad_source ("open! Base\n" ^ fixture);
        assert (run driver bad_source bad_output <> 0);
        assert (String.is_substring (read (bad_output ^ ".log")) ~substring:diagnostic)
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
        ]
        ~f:(fun (fixture, diagnostic) -> reject fixture diagnostic);
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
