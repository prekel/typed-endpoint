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
        ({ name : string; version = source.revision; display = source.name } : Target.t)]
  in
  Stdlib.print_endline (map { name = "pet"; revision = 1 }).name;
  [%expect {| override |}]
;;

module M = Typed_endpoint_mapper
module E = M.Mapping_error

module Input = struct
  type t =
    { name : string
    ; numbers : string list
    ; tail : int
    }
end

module Output = struct
  type t =
    { name : string
    ; numbers : int list
    ; tail : int
    }
end

let number text =
  match Int.of_string_opt text with
  | Some value -> Ok value
  | None -> Error (E.make ~code:"invalid_integer" ~message:"expected integer")
;;

let%expect_test "result order and nested error path" =
  let visited = ref [] in
  let map =
    [%mapper_result
      fun (source : Input.t) ->
        ({ name
         ; numbers =
             M.Converter.list
               (fun text ->
                  visited := text :: !visited;
                  number text)
               source.numbers
         ; tail =
             (visited := "tail" :: !visited;
              Ok source.tail)
         }
         : Output.t)]
  in
  (match map { name = "test"; numbers = [ "1"; "bad"; "3" ]; tail = 0 } with
   | Ok _ -> assert false
   | Error error -> Stdlib.print_endline (E.to_string error));
  [%expect {| numbers[1]: invalid_integer: expected integer |}];
  Stdlib.print_endline (String.concat ~sep:"," (List.rev !visited));
  [%expect {| 1,bad |}];
  match map { name = "ok"; numbers = [ "2" ]; tail = 7 } with
  | Error _ -> assert false
  | Ok result ->
    Stdlib.Printf.printf "%s %d %d\n" result.name (List.hd_exn result.numbers) result.tail;
    [%expect {| ok 2 7 |}]
;;

let%expect_test "option and array converters" =
  assert (Result.is_ok (M.Converter.option number None));
  assert (Result.is_ok (M.Converter.option number (Some "4")));
  (match M.Converter.array number [| "1"; "bad" |] with
   | Ok _ -> assert false
   | Error error -> Stdlib.print_endline (E.to_string error));
  [%expect {| [1]: invalid_integer: expected integer |}];
  let mapped = M.Converter.array (M.Converter.of_total Int.to_string) [| 1; 2 |] in
  match mapped with
  | Error _ -> assert false
  | Ok values ->
    Stdlib.print_endline (String.concat_array ~sep:"," values);
    [%expect {| 1,2 |}]
;;
