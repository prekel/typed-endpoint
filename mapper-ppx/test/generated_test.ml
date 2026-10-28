open! Base
module Dto = Generated_api.Dto
module Support = Generated_api.Support
module Domain = Openapi_example.Domain
module M = Typed_endpoint_mapper

let of_domain =
  [%mapper fun (source : Domain.t) -> ({ id; name; note = Support.Absent } : Dto.Pet.t)]
;;

let to_domain =
  [%mapper_result
    fun (source : Dto.Pet.t) ->
      ({ id
       ; name =
           (if String.is_empty source.name then
              Error (M.Mapping_error.make ~code:"empty_name" ~message:"name is required")
            else
              Ok source.name)
       }
       : Domain.t)]
;;

let%expect_test "generated DTO uses the same external mapper" =
  let dto = of_domain { id = 42L; name = "cat" } in
  Stdlib.print_endline (Yojson.Safe.to_string (Dto.Pet.to_yojson dto));
  [%expect {| {"id":42,"name":"cat"} |}];
  match Dto.Pet.of_yojson (`Assoc [ "id", `Int 42; "name", `String "" ]) with
  | Error message -> failwith message
  | Ok dto ->
    (match to_domain dto with
     | Ok _ -> assert false
     | Error error ->
       Stdlib.print_endline (M.Mapping_error.to_string error);
       [%expect {| name: empty_name: name is required |}])
;;

let%expect_test "generated presence stays explicit" =
  List.iter [ "{}"; "{\"note\":null}"; "{\"note\":\"value\"}" ] ~f:(fun text ->
    let fields =
      match Yojson.Safe.from_string text with
      | `Assoc fields -> fields
      | _ -> assert false
    in
    match
      Dto.Pet.of_yojson (`Assoc ([ "id", `Int 1; "name", `String "cat" ] @ fields))
    with
    | Error message -> failwith message
    | Ok dto ->
      Stdlib.print_endline
        (match dto.note with
         | Support.Absent -> "absent"
         | Support.Present None -> "null"
         | Support.Present (Some value) -> value));
  [%expect
    {|
    absent
    null
    value
    |}]
;;

let%expect_test "mapping failure does not call application service" =
  let module B = Typed_endpoint_testing in
  let module E = Typed_endpoint.Make (B) in
  let open E in
  let calls = ref 0 in
  let route =
    post / "mapped"
    |> documented ~summary:"Mapped"
    |> accepts (Request.json (module Dto.Pet))
    |> returns
         (case `OK (Response.json (module Dto.Pet))
          <|> case `Bad_request (Response.text ()))
    ==> fun ok bad_request () body ->
    match Request_body.read body with
    | Error error -> Request_body.reject error
    | Ok dto ->
      (match to_domain dto with
       | Error error -> respond bad_request (M.Mapping_error.to_string error)
       | Ok domain ->
         Int.incr calls;
         respond ok (of_domain domain))
  in
  let compiled =
    compile_exn [ Group.make_with_context ~context:(Context.return ()) [ route ] ]
  in
  let response =
    B.Client.call
      (Compiled.app compiled)
      ~headers:[ "Content-Type", "application/json" ]
      ~body:"{\"id\":1,\"name\":\"\"}"
      `POST
      "/mapped"
  in
  Stdlib.Printf.printf "%d calls=%d\n" (B.Response.status response) !calls;
  [%expect {| 400 calls=0 |}]
;;
