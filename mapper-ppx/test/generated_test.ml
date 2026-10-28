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

let non_empty_name name =
  if String.is_empty name then
    Error (M.Mapping_error.make ~code:"empty_name" ~message:"name is required")
  else
    Ok name
;;

module Handwritten : sig
  type t =
    { id : int64 [@encoding `number]
    ; name : string [@mapper.into.result non_empty_name]
    }
  [@@deriving
    yojson
  , jsonschema
  , mapper_from { source = [%type: Domain.t] }
  , mapper_into { target = [%type: Domain.t]; fallible = true }]
end = struct
  type t =
    { id : int64 [@encoding `number]
    ; name : string [@mapper.into.result non_empty_name]
    }
  [@@deriving
    yojson
  , jsonschema
  , mapper_from { source = [%type: Domain.t] }
  , mapper_into { target = [%type: Domain.t]; fallible = true }]
end

let%expect_test "code-first and contract-first outputs satisfy their schemas" =
  let domain : Domain.t = { id = 42L; name = "cat" } in
  let check schema json =
    let schema = Typed_endpoint.Json_schema.to_yojson schema in
    match Contract_test_support.validate ~document:schema ~schema json with
    | Ok () -> Stdlib.print_endline (Yojson.Safe.to_string json)
    | Error message -> failwith message
  in
  check Handwritten.t_jsonschema (Handwritten.to_yojson (Handwritten.of_domain domain));
  [%expect {| {"id":42,"name":"cat"} |}];
  check Dto.Pet.t_jsonschema (Dto.Pet.to_yojson (of_domain domain));
  [%expect {| {"id":42,"name":"cat"} |}]
;;

let%expect_test "JSON to derived DTO to application input" =
  let convert json =
    match Handwritten.of_yojson (Yojson.Safe.from_string json) with
    | Error message -> failwith message
    | Ok dto -> Handwritten.to_domain dto
  in
  (match convert "{\"id\":42,\"name\":\"cat\"}" with
   | Error error -> failwith (M.Mapping_error.to_string error)
   | Ok (input : Domain.t) -> Stdlib.Printf.printf "%Ld %s\n" input.id input.name);
  [%expect {| 42 cat |}];
  (match convert "{\"id\":42,\"name\":\"\"}" with
   | Ok _ -> assert false
   | Error error -> Stdlib.print_endline (M.Mapping_error.to_string error));
  [%expect {| name: empty_name: name is required |}]
;;

let%expect_test "derived mappers at the HTTP boundary" =
  let module B = Typed_endpoint_testing in
  let module E = Typed_endpoint.Make (B) in
  let open E in
  let calls = ref 0 in
  let application (input : Domain.t) =
    Int.incr calls;
    input
  in
  let route =
    post / "derived"
    |> documented ~summary:"Derived mapping"
    |> accepts (Request.json (module Handwritten))
    |> returns
         (case `OK (Response.json (module Handwritten))
          <|> case `Bad_request (Response.text ()))
    ==> fun ok bad_request () body ->
    match Request_body.read body with
    | Error error -> Request_body.reject error
    | Ok dto ->
      (match Handwritten.to_domain dto with
       | Error error -> respond bad_request (M.Mapping_error.to_string error)
       | Ok input -> respond ok (Handwritten.of_domain (application input)))
  in
  let compiled =
    compile_exn [ Group.make_with_context ~context:(Context.return ()) [ route ] ]
  in
  let call body =
    let response =
      B.Client.call
        (Compiled.app compiled)
        ~headers:[ "Content-Type", "application/json" ]
        ~body
        `POST
        "/derived"
    in
    Stdlib.Printf.printf "%d calls=%d\n" (B.Response.status response) !calls;
    response
  in
  let _ = call "{\"id\":1}" in
  [%expect {| 400 calls=0 |}];
  let response = call "{\"id\":1,\"name\":\"\"}" in
  [%expect {| 400 calls=0 |}];
  Stdlib.print_endline (B.Response.body response);
  [%expect {| name: empty_name: name is required |}];
  let response = call "{\"id\":1,\"name\":\"cat\"}" in
  [%expect {| 200 calls=1 |}];
  Stdlib.print_endline (B.Response.body response);
  [%expect {| {"id":1,"name":"cat"} |}]
;;
