open! Base

module Source = struct
  type t =
    { name : string
    ; revision : int
    }
end

module Target = struct
  type t =
    { name : string
    ; version : int
    ; display : string
    }
end

let project =
  [%mapper
    fun (source : Source.t) ->
      ({ name; version = source.revision; display = String.uppercase source.name }
       : Target.t)]
;;

let%expect_test "copy rename and compute" =
  let result = project { name = "pet"; revision = 3 } in
  Stdlib.Printf.printf "%s %d %s\n" result.name result.version result.display;
  [%expect {| pet 3 PET |}]
;;

let%expect_test "explicit expression preserves lexical scope" =
  let name = "override" in
  let map =
    [%mapper
      fun (source : Source.t) ->
        ({ name = (name : string); version = source.revision; display = source.name } : Target.t)]
  in
  Stdlib.print_endline (map { name = "pet"; revision = 1 }).name;
  [%expect {| override |}]
;;
