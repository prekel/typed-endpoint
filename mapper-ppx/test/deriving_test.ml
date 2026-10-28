open! Base

let%expect_test "derive projection across interfaces with explicit exceptions" =
  let source : Deriver_domain.t =
    { id = Deriver_domain.Id.of_int 42
    ; title = "cat"
    ; status = Active
    ; revision = 3
    ; internal_note = "secret"
    }
  in
  let dto = Deriver_dto.of_domain source in
  Stdlib.Printf.printf
    "%s %s %s %d %s\n"
    dto.id
    dto.name
    (match dto.status with
     | Draft -> "draft"
     | Live -> "live")
    dto.revision
    dto.display;
  [%expect {| 42 cat live 3 cat! |}];
  Stdlib.print_endline (Deriver_dto.brief_of_domain source).name;
  [%expect {| cat |}]
;;

let request : Deriver_request.t =
  { id = "42"
  ; name = "cat"
  ; priority = -3
  ; statuses = [ "draft"; "active" ]
  ; display = "ignored"
  }
;;

let%expect_test "independent directions rename convert skip and lift total fields" =
  match Deriver_request.to_domain request with
  | Error error -> failwith (Typed_endpoint_mapper.Mapping_error.to_string error)
  | Ok input ->
    let dto = Deriver_request.of_domain input in
    Stdlib.Printf.printf
      "%s %s %d %s %s\n"
      dto.id
      dto.name
      dto.priority
      (String.concat ~sep:"," dto.statuses)
      dto.display;
    [%expect {| 42 cat 3 draft,active CAT |}]
;;

let%expect_test "invalid IDs and nested enum conversion report target paths" =
  let print_error request =
    match Deriver_request.to_domain request with
    | Ok _ -> assert false
    | Error error ->
      Stdlib.print_endline (Typed_endpoint_mapper.Mapping_error.to_string error)
  in
  print_error { request with id = "bad" };
  [%expect {| project_id: invalid_id: expected positive integer |}];
  print_error { request with statuses = [ "draft"; "archived" ] };
  [%expect {| statuses[1]: invalid_status: expected draft or active |}]
;;

module Total_input = struct
  type t =
    { title : string
    ; revision : int
    }
end

module Total_request = struct
  type command =
    { name : string [@mapper.into.field "title"]
    ; revision : int
    }
  [@@deriving mapper_into { target = [%type: Total_input.t] }]
end

let%expect_test "total mapper_into has a direct return type and named function" =
  let result = Total_request.command_to_domain { name = "test"; revision = 2 } in
  Stdlib.Printf.printf "%s %d\n" result.title result.revision;
  [%expect {| test 2 |}]
;;

let%expect_test "fallible mapper_from evaluates fields once in declaration order" =
  let visited = ref [] in
  let check value =
    visited := "check" :: !visited;
    if String.is_empty value then
      Error (Typed_endpoint_mapper.Mapping_error.make ~code:"empty" ~message:"required")
    else
      Ok value
  in
  let next value =
    visited := "next" :: !visited;
    value + 1
  in
  let module Dto = struct
    type t =
      { name : string [@mapper.from.field "title"] [@mapper.from.result check]
      ; revision : int [@mapper.from.convert next]
      ; display : string
            [@mapper.from.compute
              fun (source : Total_input.t) -> String.uppercase source.title]
      }
    [@@deriving mapper_from { source = [%type: Total_input.t]; fallible = true }]
  end
  in
  (match Dto.of_domain { title = ""; revision = 1 } with
   | Ok _ -> assert false
   | Error error ->
     Stdlib.print_endline (Typed_endpoint_mapper.Mapping_error.to_string error));
  [%expect {| name: empty: required |}];
  Stdlib.print_endline (String.concat ~sep:"," (List.rev !visited));
  [%expect {| check |}];
  visited := [];
  (match Dto.of_domain { title = "cat"; revision = 1 } with
   | Error _ -> assert false
   | Ok dto -> Stdlib.Printf.printf "%s %d %s\n" dto.name dto.revision dto.display);
  [%expect {| cat 2 CAT |}];
  Stdlib.print_endline (String.concat ~sep:"," (List.rev !visited));
  [%expect {| check,next |}]
;;
