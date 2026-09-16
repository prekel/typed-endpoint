open! Base

let read_file filename =
  let channel = Stdlib.open_in_bin filename in
  let size = Stdlib.in_channel_length channel in
  let contents = Stdlib.really_input_string channel size in
  Stdlib.close_in channel;
  contents
;;

let run_compiler ~root fixture =
  let output = Stdlib.Filename.temp_file "typed-endpoint-compile-fail" ".log" in
  let include_directories =
    [ root ^ "/lib/.typed_endpoint.objs/byte"
    ; root ^ "/testing/.typed_endpoint_testing.objs/byte"
    ]
  in
  let package =
    "base,cohttp,uri,yojson,ppx_deriving_jsonschema.runtime,ppx_deriving_yojson.runtime,ppx_here.runtime-lib"
  in
  let arguments =
    [ "ocamlfind"; "ocamlc"; "-stop-after"; "typing"; "-package"; package ]
    @ List.concat_map include_directories ~f:(fun directory -> [ "-I"; directory ])
    @ [ "-c"; fixture ]
  in
  let command =
    String.concat ~sep:" " (List.map arguments ~f:Stdlib.Filename.quote)
    ^ " > "
    ^ Stdlib.Filename.quote output
    ^ " 2>&1"
  in
  let status = Stdlib.Sys.command command in
  let diagnostics = read_file output in
  Stdlib.Sys.remove output;
  status, diagnostics
;;

let require condition message =
  if not condition then
    Stdlib.failwith message
;;

let require_failure ~root ~fixture ~expected =
  let status, diagnostics = run_compiler ~root fixture in
  require (not (Int.equal status 0)) ("expected type checking to fail: " ^ fixture);
  require
    (String.is_substring diagnostics ~substring:"Error:")
    ("compiler did not report an error for " ^ fixture ^ ":\n" ^ diagnostics);
  require
    (String.is_substring diagnostics ~substring:expected)
    ("unexpected diagnostic for " ^ fixture ^ ":\n" ^ diagnostics)
;;

let () =
  match Stdlib.Array.to_list Stdlib.Sys.argv with
  | [ _; root; valid; wrong_payload; wrong_status; wrong_handler; wrong_stage ] ->
    let status, diagnostics = run_compiler ~root valid in
    require
      (Int.equal status 0)
      ("expected type checking to succeed from "
       ^ root
       ^ " while running in "
       ^ Stdlib.Sys.getcwd ()
       ^ ": "
       ^ valid
       ^ "\n"
       ^ diagnostics);
    require_failure ~root ~fixture:wrong_payload ~expected:"is not compatible with type";
    require_failure ~root ~fixture:wrong_status ~expected:"Response.case";
    require_failure
      ~root
      ~fixture:wrong_handler
      ~expected:"is not compatible with type unit";
    require_failure ~root ~fixture:wrong_stage ~expected:"This expression has type"
  | _ -> Stdlib.failwith "expected workspace root and five compile-fail fixtures"
;;
