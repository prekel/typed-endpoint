open! Base
module Api = Typed_endpoint_openapi

let read path =
  let channel = Stdlib.open_in_bin path in
  Exn.protect
    ~f:(fun () -> Yojson.Safe.from_channel channel)
    ~finally:(fun () -> Stdlib.close_in channel)
;;

let () =
  let inputs = ref []
  and config = ref ""
  and output = ref "" in
  let flags =
    [ ( "--input"
      , Stdlib.Arg.String (fun path -> inputs := (None, path) :: !inputs)
      , "Input JSON (repeatable)" )
    ; ( "--group-input"
      , Stdlib.Arg.String
          (fun value ->
            match String.lsplit2 value ~on:'=' with
            | Some (group, path) when not (String.is_empty group || String.is_empty path)
              -> inputs := (Some group, path) :: !inputs
            | _ -> raise (Stdlib.Arg.Bad "--group-input expects GROUP=FILE"))
      , "Group and input JSON (repeatable)" )
    ; "--config", Stdlib.Arg.Set_string config, "Configuration JSON"
    ; "--output-dir", Stdlib.Arg.Set_string output, "Existing output directory"
    ]
  in
  let run () =
    Stdlib.Arg.parse
      flags
      (fun arg ->
         if not (String.equal arg "generate") then
           raise (Stdlib.Arg.Bad (Stdlib.Printf.sprintf "unexpected argument %s" arg)))
      "typed-endpoint-openapi generate --input FILE --output-dir DIR";
    if List.is_empty !inputs || String.is_empty !output then
      raise
        (Stdlib.Arg.Bad
           "at least one --input or --group-input and --output-dir are required");
    let config =
      if String.is_empty !config then
        Ok Api.Config.default
      else
        Api.Config.of_yojson (read !config)
    in
    match
      Result.bind config ~f:(fun config ->
        match !inputs with
        | [ (None, path) ] -> Api.generate ~config (read path)
        | inputs ->
          Api.generate_sources
            ~config
            (List.map inputs ~f:(fun (group, path) ->
               { Api.Source.name =
                   Option.value group ~default:(Stdlib.Filename.basename path)
               ; group
               ; document = read path
               })))
    with
    | Error errors ->
      List.iter errors ~f:(fun e -> Stdlib.prerr_endline (Api.Diagnostic.to_string e));
      Stdlib.exit 1
    | Ok files ->
      List.iter files ~f:(fun (file : Api.Generated_file.t) ->
        let path = Stdlib.Filename.concat !output file.path in
        let channel = Stdlib.open_out_bin path in
        Exn.protect
          ~f:(fun () -> Stdlib.output_string channel file.contents)
          ~finally:(fun () -> Stdlib.close_out channel))
  in
  try run () with
  | Stdlib.Arg.Bad message | Yojson.Json_error message | Stdlib.Sys_error message ->
    Stdlib.prerr_endline message;
    Stdlib.exit 1
;;
