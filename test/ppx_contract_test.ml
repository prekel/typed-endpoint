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

let run driver source output =
  let command =
    String.concat
      ~sep:" "
      (List.map [ driver; "--impl"; source; "-o"; output ] ~f:Stdlib.Filename.quote)
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
      write
        bad_source
        {|
open! Base
type maybe_string = string option [@@deriving jsonschema]
type t = { value : maybe_string [@jsonschema.option] } [@@deriving jsonschema]
|};
      assert (run driver bad_source bad_output <> 0);
      assert (
        String.is_substring
          (read (bad_output ^ ".log"))
          ~substring:"requires a shared [@default]");
      write
        bad_source
        {|
open! Base
type maybe_string = string option [@@deriving jsonschema]
type t = { value : maybe_string [@jsonschema.option] [@default None] } [@@deriving jsonschema]
|};
      assert (run driver bad_source bad_output = 0))
    ~finally:(fun () ->
      List.iter [ first; second ] ~f:(fun folder ->
        Stdlib.Sys.readdir folder
        |> Stdlib.Array.iter (fun name -> Stdlib.Sys.remove (folder ^ "/" ^ name));
        Unix.rmdir folder);
      Unix.rmdir directory)
;;
