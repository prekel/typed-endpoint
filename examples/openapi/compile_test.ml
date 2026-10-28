open! Base

let read path =
  let c = Stdlib.open_in_bin path in
  Exn.protect
    ~f:(fun () -> Stdlib.really_input_string c (Stdlib.in_channel_length c))
    ~finally:(fun () -> Stdlib.close_in c)
;;

let () =
  match Stdlib.Array.to_list Stdlib.Sys.argv with
  | [ _; core; testing; generated; valid; missing; wrong ] ->
    let includes =
      List.concat_map [ core; testing; generated ] ~f:(fun p ->
        [ "-I"; Stdlib.Filename.dirname p ])
    in
    let check file expected =
      let log = Stdlib.Filename.temp_file "openapi-typecheck" ".log" in
      Exn.protect
        ~finally:(fun () -> Stdlib.Sys.remove log)
        ~f:(fun () ->
          let args =
            [ "ocamlfind"
            ; "ocamlc"
            ; "-stop-after"
            ; "typing"
            ; "-package"
            ; "base,yojson,ppx_deriving_yojson.runtime,ppx_here.runtime-lib"
            ]
            @ includes @ [ "-c"; file ]
          in
          let command =
            Stdlib.Printf.sprintf
              "%s > %s 2>&1"
              (String.concat ~sep:" " (List.map args ~f:Stdlib.Filename.quote))
              (Stdlib.Filename.quote log)
          in
          let status = Stdlib.Sys.command command in
          match expected with
          | None ->
            if status <> 0 then
              Stdlib.failwith (read log)
          | Some text ->
            if status = 0 || not (String.is_substring (read log) ~substring:text) then
              Stdlib.failwith ("unexpected typecheck result: " ^ read log))
    in
    check valid None;
    check missing (Some "create_pet");
    check wrong (Some "string")
  | _ -> Stdlib.failwith "invalid compiler test arguments"
;;
