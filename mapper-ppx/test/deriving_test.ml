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
