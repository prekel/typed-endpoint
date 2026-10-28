open! Base
module B = Typed_endpoint_testing
module S = Grouped_api.Server.Make (B)
module E = S.Endpoint
module D = Grouped_api.Dto
module O = Grouped_api.Operations

let pet : D.Pet.t = { id = 1L; note = None }

let compiled () =
  let context = E.Context.return () in
  let groups =
    S.Catalog.groups
      ~context
      ~decode_errors:()
      { catalog_pet = (fun () () -> O.Catalog_pet.Response.Status_200 pet) }
    @ S.Admin.groups
        ~context
        ~decode_errors:
          { save_pet_400 = (fun _ -> "bad request")
          ; save_pet_413 = (fun _ -> "too large")
          ; save_pet_415 = (fun _ -> "unsupported")
          }
        { save_pet =
            (fun () (r : O.Save_pet.Request.t) ->
              (* Both groups and the request share exactly D.Pet.t. *)
              let shared : O.Catalog_pet.Response_200.t = r.body in
              O.Save_pet.Response.Status_200 shared)
        ; probe =
            (fun () () ->
              O.Probe.Response.Status_200
                { kind = D.Get_probe_response_200_kind.Ok
                ; nothing = ()
                ; anything = `List [ `Int 1; `Null ]
                ; score = 2.
                })
        }
  in
  E.compile_exn groups
;;

let call ?headers ?body meth path =
  let response = B.Client.call (E.Compiled.app (compiled ())) ?headers ?body meth path in
  Stdlib.Printf.printf "%d %s\n" (B.Response.status response) (B.Response.body response)
;;

let%expect_test "separate documents share DTOs and preserve absolute paths" =
  call `GET "/v1/catalog/pet";
  [%expect {| 200 {"id":1,"note":null} |}];
  call
    ~headers:[ "content-type", "application/json" ]
    ~body:{|{"id":2,"note":"shared"}|}
    `POST
    "/v1/admin/pet";
  [%expect {| 200 {"id":2,"note":"shared"} |}];
  call
    ~headers:[ "content-type", "application/json" ]
    ~body:{|{"id":2}|}
    `POST
    "/v1/admin/pet";
  [%expect {| 400 "bad request" |}];
  call `GET "/probe";
  [%expect {| 200 {"anything":[1,null],"kind":"ok","nothing":null,"score":2.0} |}]
;;

let%expect_test "3.2.1 export keeps JSON Schema semantics" =
  let doc =
    E.Compiled.export_openapi ~spec_version:V3_2_1 (compiled ())
    |> Result.map_error ~f:(fun es ->
      String.concat
        ~sep:"; "
        (List.map es ~f:Typed_endpoint.Openapi.Export_error.to_string))
    |> Result.ok_or_failwith
  in
  Stdlib.print_endline Yojson.Safe.Util.(doc |> member "openapi" |> to_string);
  [%expect {| 3.2.1 |}];
  let schema =
    Yojson.Safe.Util.(
      doc
      |> member "components"
      |> member "schemas"
      |> member "Get_probe_response_200"
      |> member "properties")
  in
  assert (Yojson.Safe.equal (Yojson.Safe.Util.member "anything" schema) (`Assoc []));
  assert (
    Yojson.Safe.equal
      Yojson.Safe.Util.(schema |> member "score" |> member "exclusiveMinimum")
      (`Int 1));
  assert (
    Yojson.Safe.equal
      Yojson.Safe.Util.(schema |> member "kind" |> member "const")
      (`String "ok"));
  Stdlib.print_endline "constraints preserved";
  [%expect {| constraints preserved |}]
;;

let%expect_test "each group exposes its own document metadata" =
  List.iter [ S.Catalog.openapi_config; S.Admin.openapi_config ] ~f:(fun config ->
    let doc = E.Compiled.openapi ~config (compiled ()) in
    Stdlib.print_endline
      Yojson.Safe.Util.(doc |> member "info" |> member "title" |> to_string));
  [%expect
    {| 
    Catalog API
    Admin API |}]
;;
