open! Base

let write path contents =
  let channel = Stdlib.open_out path in
  Exn.protect
    ~f:(fun () -> Stdlib.output_string channel contents)
    ~finally:(fun () -> Stdlib.close_out channel)
;;

let () =
  let driver = Stdlib.Sys.argv.(1) in
  let path = Stdlib.Filename.temp_file "mapper_compile" ".ml" in
  let log = path ^ ".log" in
  Exn.protect
    ~finally:(fun () -> List.iter [ path; log ] ~f:Stdlib.Sys.remove)
    ~f:(fun () ->
      List.iter
        [ "type t = { name : string }", "{ name }", true
        ; "type t = { name : string; added : int }", "{ name }", false
        ; "type t = { name : int }", "{ name }", false
        ; "type t = { title : string }", "{ title = source.missing }", false
        ; "type t = { name : string }", "{ name; extra = 1 }", false
        ]
        ~f:(fun (target, body, success) ->
          write
            path
            ("module Source = struct type t = { name : string; ignored : int } end\nmodule Target = struct "
           ^ target ^ " end\nlet map = [%mapper fun (source : Source.t) -> (" ^ body
           ^ " : Target.t)]\n");
          let command =
            String.concat
              ~sep:" "
              (List.map
                 [ "ocamlc"
                 ; "-stop-after"
                 ; "typing"
                 ; "-ppx"
                 ; driver ^ " -as-ppx"
                 ; "-c"
                 ; path
                 ]
                 ~f:Stdlib.Filename.quote)
          in
          let code =
            Stdlib.Sys.command (command ^ " > " ^ Stdlib.Filename.quote log ^ " 2>&1")
          in
          if not (Bool.equal (code = 0) success) then
            failwith ("unexpected compiler result for " ^ target)))
;;
