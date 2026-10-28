open! Base

let write path contents =
  let channel = Stdlib.open_out path in
  Exn.protect
    ~f:(fun () -> Stdlib.output_string channel contents)
    ~finally:(fun () -> Stdlib.close_out channel)
;;

let read path =
  let channel = Stdlib.open_in path in
  Exn.protect
    ~f:(fun () -> Stdlib.really_input_string channel (Stdlib.in_channel_length channel))
    ~finally:(fun () -> Stdlib.close_in channel)
;;

let () =
  let driver = Stdlib.Sys.argv.(1) in
  let runtime = Stdlib.Filename.dirname Stdlib.Sys.argv.(2) in
  let path = Stdlib.Filename.temp_file "mapper_compile" ".ml" in
  let log = path ^ ".log" in
  let source = "module Source = struct type t = { name : string; ignored : int } end\n" in
  let target = "module Target = struct type t = { name : string } end\n" in
  let map = "let map = [%mapper fun (source : Source.t) -> ({ name } : Target.t)]" in
  Exn.protect
    ~finally:(fun () -> List.iter [ path; log ] ~f:Stdlib.Sys.remove)
    ~f:(fun () ->
      let check declarations expression diagnostic =
        write path (declarations ^ expression ^ "\n");
        let command =
          String.concat
            ~sep:" "
            (List.map
               [ "ocamlfind"
               ; "ocamlc"
               ; "-package"
               ; "base"
               ; "-I"
               ; runtime
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
        let output = read log in
        match diagnostic with
        | None ->
          if code <> 0 then
            failwith output
        | Some fragment ->
          if code = 0 || not (String.is_substring output ~substring:fragment) then
            failwith ("expected diagnostic: " ^ fragment ^ "\n" ^ output)
      in
      check (source ^ target) map None;
      List.iter
        [ "type t = { name : string; added : int }", "{ name }", "added"
        ; "type t = { name : int }", "{ name }", "string"
        ; "type t = { title : string }", "{ title = source.missing }", "missing"
        ; "type t = { name : string }", "{ name; extra = 1 }", "extra"
        ]
        ~f:(fun (target_type, body, diagnostic) ->
          check
            (source ^ "module Target = struct " ^ target_type ^ " end\n")
            ("let map = [%mapper fun (source : Source.t) -> (" ^ body ^ " : Target.t)]")
            (Some diagnostic));
      let strict =
        "let map = [%mapper fun ({ name = n; ignored = _ } : Source.t) -> ({ name = n } : Target.t)]"
      in
      check (source ^ target) strict None;
      check
        ("module Source = struct type t = { name : string; ignored : int; added : bool } end\n"
       ^ target)
        strict
        (Some "added");
      check
        (source ^ target)
        "let map = [%mapper fun (source : Source.t) -> ({source with name = \"x\"} : Target.t)]"
        (Some "complete target record");
      check
        (source ^ target)
        "let map = [%mapper fun source -> ({name} : Target.t)]"
        (Some "expected fun");
      check
        (source ^ target)
        "let map = [%mapper_result fun (source : Source.t) -> ({name = Ok 1} : Target.t)]"
        (Some "int");
      let derive fields =
        "type t = { " ^ fields
        ^ " } [@@deriving mapper_from {source = [%type: Source.t]}]"
      in
      check source (derive "name : string") None;
      check source (derive "name : string; added : int") (Some "added");
      check source (derive "name : int") (Some "string");
      check
        source
        (derive "title : string [@mapper.from.field \"missing\"]")
        (Some "missing");
      check
        source
        (derive
           "name : string [@mapper.from.compute (fun _ -> \"x\")] [@mapper.from.field \"name\"]")
        (Some "compute cannot be combined");
      check
        source
        (derive
           "name : string [@mapper.from.compute (fun _ -> \"x\")] [@mapper.from.convert Fun.id]")
        (Some "compute cannot be combined");
      check
        source
        "type t = string [@@deriving mapper_from {source = [%type: Source.t]}]"
        (Some "expected a record");
      check
        source
        "type 'a t = {name : 'a} [@@deriving mapper_from {source = [%type: Source.t]}]"
        (Some "parameterized DTOs");
      check
        source
        "type t = {name : string} [@@deriving mapper_from]"
        (Some "expected source");
      let different_ids =
        "module A : sig type t end = struct type t = string end\nmodule B : sig type t end = struct type t = string end\nmodule Source = struct type t = {name : A.t} end\nmodule Target = struct type t = {name : B.t} end\n"
      in
      check different_ids map (Some "A.t");
      check
        "module Source = struct type status = Draft | Active type t = { name : status } end\nmodule Target = struct type status = Draft | Active type t = { name : status } end\n"
        map
        (Some "Source.status");
      check
        "module Source = struct type t = Draft | Active end\n"
        "let map = (function Source.Draft -> 0) [@@warning \"+8\"] [@@warnerror \"+8\"]"
        (Some "Active"))
;;
