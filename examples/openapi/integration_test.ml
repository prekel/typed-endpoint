open! Base
module B = Typed_endpoint_testing
module S = Generated_api.Server.Make (B)
module E = S.Endpoint
module D = Generated_api.Dto
module O = Generated_api.Operations
module C = Openapi_example.Pet_controller.Make (B)

let bad _ : D.Api_error.t = { message = "Invalid request" }
let pets = [ Openapi_example.Domain.{ id = 1L; name = "Milo" } ]

let groups () =
  S.Wire.groups
    ~context:(E.Context.return ())
    ~decode_errors:
      { echo_wire_400 = bad
      ; echo_wire_413 = (fun _ -> { limit = 1048576L })
      ; echo_wire_415 = (fun _ -> { expected = "application/json" })
      }
    { echo_wire =
        (fun () (r : O.Echo_wire.Request.t) -> O.Echo_wire.Response.Status_200 r.body)
    }
  @ S.Health.groups
      ~context:(E.Context.return ())
      ~decode_errors:()
      { health = (fun () () -> O.Health.Response.Status_204 ()) }
  @ S.Pets.groups
      ~context:(E.Context.return pets)
      ~decode_errors:
        { create_pet_400 = bad
        ; get_pet_400 = bad
        ; search_pets_400 = bad
        ; create_pet_413 = (fun _ -> { limit = 1048576L })
        ; create_pet_415 = (fun _ -> { expected = "application/json" })
        }
      { create_pet = C.create
      ; get_pet = C.get
      ; search_pets =
          (fun pets (_ : O.Search_pets.Request.t) ->
            O.Search_pets.Response.Status_200
              { body = List.map pets ~f:Openapi_example.Pet_mapping.of_domain
              ; header_x_count = Int64.of_int (List.length pets)
              ; header_x_mode = Some "search"
              })
      }
  @ S.Animals.groups
      ~context:(E.Context.return ())
      ~decode_errors:
        { echo_animal_400 = bad
        ; echo_animal_413 = (fun _ -> { limit = 1048576L })
        ; echo_animal_415 = (fun _ -> { expected = "application/json" })
        }
      { echo_animal =
          (fun () (r : O.Echo_animal.Request.t) ->
            O.Echo_animal.Response.Status_200 r.body)
      }
  @ S.Labels.groups
      ~context:(E.Context.return ())
      ~decode_errors:
        { echo_label_400 = bad
        ; echo_label_413 = (fun _ -> { limit = 1048576L })
        ; echo_label_415 = (fun _ -> { expected = "application/json" })
        }
      { echo_label =
          (fun () (r : O.Echo_label.Request.t) -> O.Echo_label.Response.Status_200 r.body)
      }
;;

let compiled () = E.compile_exn (groups ())

(* A separate test normalization lets the JSON Schema validator read the
   original 3.0.3 fixture. It does not use the generator's imported schemas. *)
let source_document =
  let input = Stdlib.open_in_bin "openapi.json" in
  let json =
    Exn.protect
      ~f:(fun () -> Yojson.Safe.from_channel input)
      ~finally:(fun () -> Stdlib.close_in input)
  in
  let rec convert = function
    | `Assoc fields ->
      let nullable = List.Assoc.find fields "nullable" ~equal:String.equal in
      `Assoc
        (List.filter_map fields ~f:(fun (k, v) ->
           if String.equal k "nullable" then
             None
           else (
             let v =
               if
                 String.equal k "type"
                 && Option.value_map
                      nullable
                      ~default:false
                      ~f:(Yojson.Safe.equal (`Bool true))
               then
                 `List [ v; `String "null" ]
               else
                 convert v
             in
             Some (k, v))))
    | `List xs -> `List (List.map xs ~f:convert)
    | x -> x
  in
  convert json
;;

let call ?headers ?body meth target =
  let response =
    B.Client.call (E.Compiled.app (compiled ())) ?headers ?body meth target
  in
  let method_name = Contract_test_support.method_name meth in
  let path =
    Contract_test_support.path_for_target_exn source_document ~meth:method_name ~target
  in
  Contract_test_support.response_exn
    ~document:source_document
    ~path
    ~meth:method_name
    ~status:(B.Response.status response)
    ~headers:(B.Response.headers response)
    ~body:(B.Response.body response);
  response
;;

let print_response r =
  Stdlib.Printf.printf "%d %s\n" (B.Response.status r) (B.Response.body r)
;;

let%expect_test "handwritten mapping and path decode error" =
  print_response (call `GET "/pets/1");
  [%expect {| 200 {"id":1,"name":"Milo"} |}];
  print_response (call `GET "/pets/no-number");
  [%expect {| 400 {"message":"Invalid request"} |}]
;;

let%expect_test "missing, null and value remain distinct" =
  let check raw =
    let value = D.Pet.of_yojson (Yojson.Safe.from_string raw) |> Result.ok_or_failwith in
    let state =
      match value.note with
      | Generated_api.Support.Absent -> "absent"
      | Present None -> "null"
      | Present (Some _) -> "value"
    in
    Stdlib.Printf.printf "%s %s\n" state (Yojson.Safe.to_string (D.Pet.to_yojson value))
  in
  check {|{"id":1,"name":"Milo"}|};
  [%expect {| absent {"id":1,"name":"Milo"} |}];
  check {|{"id":1,"name":"Milo","note":null}|};
  [%expect {| null {"id":1,"name":"Milo","note":null} |}];
  check {|{"id":1,"name":"Milo","note":"hello"}|};
  [%expect {| value {"id":1,"name":"Milo","note":"hello"} |}]
;;

let%expect_test "automatic statuses use distinct declared DTOs" =
  print_response (call ~body:"{}" `POST "/pets");
  [%expect {| 415 {"expected":"application/json"} |}];
  print_response
    (call ~headers:[ "content-type", "application/json" ] ~body:"{}" `POST "/pets");
  [%expect {| 400 {"message":"Invalid request"} |}];
  print_response
    (call
       ~headers:[ "content-type", "application/json" ]
       ~body:(String.make 1048577 ' ')
       `POST
       "/pets");
  [%expect {| 413 {"limit":1048576} |}]
;;

let%expect_test "discriminator and object intersection" =
  print_response
    (call
       ~headers:[ "content-type", "application/json" ]
       ~body:{|{"kind":"error","bark":true}|}
       `POST
       "/animals");
  [%expect {| 200 {"bark":true,"kind":"error"} |}];
  print_response
    (call
       ~headers:[ "content-type", "application/json" ]
       ~body:{|{"id":2,"label":"hello","extra":true}|}
       `POST
       "/labels");
  [%expect {| 200 {"id":2,"label":"hello","extra":true} |}]
;;

let%expect_test "export versions preserve the legacy default" =
  let c = compiled () in
  List.iter
    [ Typed_endpoint.Openapi.Spec_version.V3_0_3; V3_1_0; V3_2_1 ]
    ~f:(fun spec_version ->
      match E.Compiled.export_openapi ~spec_version c with
      | Error es ->
        Stdlib.print_endline
          (String.concat
             ~sep:"\n"
             (List.map es ~f:Typed_endpoint.Openapi.Export_error.to_string))
      | Ok doc ->
        Stdlib.print_endline Yojson.Safe.Util.(doc |> member "openapi" |> to_string));
  [%expect
    {| 
    3.0.3
    3.1.0
    3.2.1 |}];
  let current = E.Compiled.openapi c in
  let explicit =
    E.Compiled.export_openapi ~spec_version:V3_1_0 c
    |> Result.map_error ~f:(fun es ->
      String.concat
        ~sep:"; "
        (List.map es ~f:Typed_endpoint.Openapi.Export_error.to_string))
    |> Result.ok_or_failwith
  in
  assert (Yojson.Safe.equal current explicit)
;;

let%expect_test "static route, enum query, repeated array and response headers" =
  let r = call `GET "/pets/search?tags=a&tags=b&status=available" in
  print_response r;
  [%expect {| 200 [{"id":1,"name":"Milo"}] |}];
  Stdlib.print_endline (Option.value (B.Response.header r "x-count") ~default:"missing");
  [%expect {| 1 |}];
  Stdlib.print_endline (Option.value (B.Response.header r "x-mode") ~default:"missing");
  [%expect {| search |}];
  print_response (call `GET "/pets/search?status=unknown");
  [%expect {| 400 {"message":"Invalid request"} |}]
;;

let%expect_test "invalid requests do not invoke application handlers" =
  let groups =
    S.Pets.groups
      ~context:(E.Context.return ())
      ~decode_errors:
        { create_pet_400 = bad
        ; get_pet_400 = bad
        ; search_pets_400 = bad
        ; create_pet_413 = (fun _ -> { limit = 1048576L })
        ; create_pet_415 = (fun _ -> { expected = "application/json" })
        }
      { create_pet = (fun () _ -> assert false)
      ; get_pet = (fun () _ -> assert false)
      ; search_pets = (fun () _ -> assert false)
      }
  in
  let app = E.Compiled.app (E.compile_exn groups) in
  let r =
    B.Client.call
      app
      ~headers:[ "content-type", "application/json" ]
      ~body:"{}"
      `POST
      "/pets"
  in
  print_response r;
  [%expect {| 400 {"message":"Invalid request"} |}]
;;

let%expect_test "body-less generated operation needs no decode mapper" =
  let response = call `GET "/health" in
  Stdlib.Printf.printf "%d %S\n" (B.Response.status response) (B.Response.body response);
  [%expect {| 204 "" |}];
  assert (Option.is_none (B.Response.header response "content-type"))
;;

let%expect_test "derived codecs preserve wire names after identifier normalization" =
  print_response
    (call
       ~headers:[ "content-type", "application/json" ]
       ~body:{|{"displayName":"Name","foo-bar":"a","foo_bar":"b"}|}
       `POST
       "/wire");
  [%expect {| 200 {"displayName":"Name","foo-bar":"a","foo_bar":"b"} |}]
;;

let%expect_test "operation, body and parameter metadata come from the contract" =
  let doc = E.Compiled.openapi (compiled ()) in
  let post =
    Yojson.Safe.Util.(doc |> member "paths" |> member "/pets" |> member "post")
  in
  Stdlib.print_endline
    (Yojson.Safe.to_string Yojson.Safe.Util.(post |> member "deprecated"));
  [%expect {| true |}];
  Stdlib.print_endline
    Yojson.Safe.Util.(post |> member "requestBody" |> member "description" |> to_string);
  [%expect {| Pet input |}];
  let params =
    Yojson.Safe.Util.(
      doc
      |> member "paths"
      |> member "/pets/search"
      |> member "get"
      |> member "parameters"
      |> to_list)
  in
  let tags =
    List.find_exn params ~f:(fun p ->
      String.equal Yojson.Safe.Util.(p |> member "name" |> to_string) "tags")
  in
  Stdlib.print_endline Yojson.Safe.Util.(tags |> member "description" |> to_string);
  [%expect {| Repeated tags |}]
;;
