open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson
open Typed_endpoint

module Test_backend = struct
  type req =
    { params : (string * string) list
    ; queries : (string * string) list
    ; body : string
    }

  type resp =
    { status : int
    ; body : string
    }

  include Cohttp.Code

  type handler = req -> resp Lwt.t
  type app_builder = (meth * string * handler) list

  let get = `GET
  let post = `POST
  let put = `PUT
  let delete = `DELETE
  let patch = `PATCH
  let route meth path handler = [ meth, path, handler ]
  let param request name = List.Assoc.find_exn request.params name ~equal:String.equal
  let query request name = List.Assoc.find request.queries name ~equal:String.equal
  let body_to_string (request : req) = Lwt.return request.body

  let respond_string ?(status = `OK) body =
    Lwt.return { status = code_of_status status; body }
  ;;

  let respond_json ?(status = `OK) body =
    respond_string ~status (Yojson.Safe.to_string body)
  ;;

  let combine = List.append
  let empty = []
end

module Endpoint = Make (Test_backend)
open Endpoint
open Endpoint.D

module Int_param = struct
  type t = int [@@deriving jsonschema]

  let of_string value =
    try Ok (Int.of_string value) with
    | _ -> Error "not an integer"
  ;;

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Integer parameter" ()
  ;;
end

module Parse_body = struct
  type t = { source : string } [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Parse error" ()
  ;;
end

module Business_error = struct
  type t = { message : string } [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Business error" ()
  ;;
end

let parse_policy ~status source =
  Parse_error_response.json
    ~status
    ~payload:(module Parse_body)
    ~map:(fun _error -> Parse_body.{ source })
;;

let group routes =
  Group.v ~metadata:(Operation_metadata.v ~description:"Test routes" ()) routes
;;

let print_compile_result groups =
  match compile groups with
  | Ok _ -> Stdlib.print_endline "ok"
  | Error errors ->
    List.iter errors ~f:(fun error ->
      Stdlib.print_endline (Compile_error.to_string error))
;;

let duplicate_route =
  make
    ~meth:B.get
    ~path:(s "duplicate" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"OK" ()))
  @@ fun _request () -> Lwt.return (OK "ok")
;;

let%expect_test "duplicate routes are rejected" =
  print_compile_result [ group [ duplicate_route; duplicate_route ] ];
  [%expect {| duplicate route: get /duplicate |}]
;;

let operation route_path =
  make
    ~meth:B.get
    ~operation_id:"duplicateOperation"
    ~path:(s route_path /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"OK" ()))
  @@ fun _request () -> Lwt.return (OK "ok")
;;

let%expect_test "duplicate operation ids are rejected" =
  print_compile_result [ group [ operation "one"; operation "two" ] ];
  [%expect {| duplicate operationId: duplicateOperation |}]
;;

let missing_parse_error_policy =
  make
    ~meth:B.get
    ~path:(s "users" / param "id" (module Int_param) /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"OK" ()))
  @@ fun id _request () -> Lwt.return (OK (Int.to_string id))
;;

let%expect_test "fallible input requires an explicit parse-error policy" =
  print_compile_result [ group [ missing_parse_error_policy ] ];
  [%expect {| missing parse-error policy: get /users/:id |}]
;;

let parsing_route ?parse_error route_path =
  make
    ~meth:B.get
    ?parse_error
    ~path:(s route_path / param "id" (module Int_param) /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"OK" ()))
  @@ fun id _request () -> Lwt.return (OK (Int.to_string id))
;;

let response_at compiled path =
  let _, _, handler =
    Compiled.app compiled
    |> List.find_exn ~f:(fun (_, route_path, _) -> String.equal path route_path)
  in
  let request = Test_backend.{ params = [ "id", "invalid" ]; queries = []; body = "" } in
  match Lwt.state (handler request) with
  | Return response -> response
  | Fail error -> Stdlib.raise error
  | Sleep -> failwith "unexpected pending response"
;;

let%expect_test "parse-error policies inherit from endpoint, group, and compile" =
  let compile_policy = parse_policy ~status:`Bad_request "compile" in
  let group_policy = parse_policy ~status:`Unprocessable_entity "group" in
  let endpoint_policy = parse_policy ~status:`Conflict "endpoint" in
  let groups =
    [ group [ parsing_route "compile" ]
    ; Group.v
        ~parse_error:group_policy
        ~metadata:(Operation_metadata.v ~description:"Group override" ())
        [ parsing_route "group" ]
    ; Group.v
        ~parse_error:group_policy
        ~metadata:(Operation_metadata.v ~description:"Endpoint override" ())
        [ parsing_route ~parse_error:endpoint_policy "endpoint" ]
    ]
  in
  let compiled = compile_exn ~parse_error:compile_policy groups in
  List.iter [ "/compile/:id"; "/group/:id"; "/endpoint/:id" ] ~f:(fun path ->
    let response = response_at compiled path in
    Stdlib.Printf.printf "%d %s\n" response.status response.body);
  [%expect
    {|
    400 {"source":"compile"}
    422 {"source":"group"}
    409 {"source":"endpoint"}
    |}]
;;

let response_schema compiled path_name status =
  let open Yojson.Safe.Util in
  Compiled.openapi compiled
  |> member "paths"
  |> member path_name
  |> member "get"
  |> member "responses"
  |> member (Int.to_string status)
  |> member "content"
  |> member "application/json"
  |> member "schema"
;;

let schema_route ~business_schema route_path =
  make
    ~meth:B.get
    ~path:(s route_path / param "id" (module Int_param) /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"OK" ()) |+ bad_request business_schema)
  @@ fun _id _request () -> Lwt.return (OK "ok")
;;

let%expect_test "parse-error schemas are deduplicated or combined with oneOf" =
  let policy = parse_policy ~status:`Bad_request "parse" in
  let same =
    schema_route ~business_schema:(Response.json (module Parse_body)) "same-schema"
  in
  let different =
    schema_route
      ~business_schema:(Response.json (module Business_error))
      "different-schema"
  in
  let static =
    make
      ~meth:B.get
      ~path:(s "static" /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.text ~description:"OK" ()))
    @@ fun _request () -> Lwt.return (OK "ok")
  in
  let compiled = compile_exn ~parse_error:policy [ group [ same; different; static ] ] in
  let open Yojson.Safe.Util in
  let same_one_of = response_schema compiled "/same-schema/{id}" 400 |> member "oneOf" in
  let different_one_of =
    response_schema compiled "/different-schema/{id}" 400
    |> member "oneOf"
    |> to_list
    |> List.length
  in
  let static_parse_response =
    Compiled.openapi compiled
    |> member "paths"
    |> member "/static"
    |> member "get"
    |> member "responses"
    |> member "400"
  in
  Stdlib.Printf.printf
    "same_one_of=%b different_one_of=%d static_parse_response=%b"
    (not (Yojson.Safe.equal same_one_of `Null))
    different_one_of
    (not (Yojson.Safe.equal static_parse_response `Null));
  [%expect {| same_one_of=false different_one_of=2 static_parse_response=false |}]
;;

let empty_response_family =
  make
    ~meth:B.get
    ~path:(s "empty-family" /? nil)
    ~request:Request.empty
    ~responses:(code4xx [] (Response.text ~description:"Error" ()))
  @@ fun _request () -> Lwt.return (Code_4xx (`Conflict, "error"))
;;

let%expect_test "empty response families are rejected" =
  print_compile_result [ group [ empty_response_family ] ];
  [%expect {| empty response status family: get /empty-family |}]
;;

let invalid_no_content_response =
  make
    ~meth:B.get
    ~path:(s "invalid-no-content" /? nil)
    ~request:Request.empty
    ~responses:(code2xx [ `No_content ] (Response.text ~description:"Invalid" ()))
  @@ fun _request () -> Lwt.return (Code_2xx (`No_content, "body"))
;;

let%expect_test "204 responses cannot carry a payload" =
  print_compile_result [ group [ invalid_no_content_response ] ];
  [%expect {| 204 response must use an empty payload: get /invalid-no-content |}]
;;

let duplicate_response_status =
  make
    ~meth:B.get
    ~path:(s "duplicate-status" /? nil)
    ~request:Request.empty
    ~responses:(code [ `Code 418; `Code 418 ] (Response.text ~description:"Error" ()))
  @@ fun _request () -> Lwt.return (Code (`Code 418, "error"))
;;

let%expect_test "duplicate response statuses are rejected" =
  print_compile_result [ group [ duplicate_response_status ] ];
  [%expect {| duplicate response status 418: get /duplicate-status |}]
;;

let undeclared_runtime_status =
  make
    ~meth:B.get
    ~path:(s "runtime-status" /? nil)
    ~request:Request.empty
    ~responses:(code4xx [ `Conflict ] (Response.text ~description:"Error" ()))
  @@ fun _request () -> Lwt.return (Code_4xx (`Gone, "gone"))
;;

let%expect_test "runtime rejects a status outside its declared family" =
  let compiled = compile_exn [ group [ undeclared_runtime_status ] ] in
  let _, _, handler = List.hd_exn (Compiled.app compiled) in
  let request = Test_backend.{ params = []; queries = []; body = "" } in
  (match
     try `Promise (handler request) with
     | Runtime_error error -> `Runtime_error error
   with
   | `Runtime_error error -> Stdlib.print_endline (Runtime_error.to_string error)
   | `Promise promise ->
     (match Lwt.state promise with
      | Lwt.Fail (Runtime_error error) ->
        Stdlib.print_endline (Runtime_error.to_string error)
      | Lwt.Fail error -> Stdlib.raise error
      | Lwt.Return _ -> Stdlib.print_endline "unexpected response"
      | Lwt.Sleep -> Stdlib.print_endline "unexpected pending response"));
  [%expect
    {|
    handler returned undeclared status 410 for get /runtime-status; declared: [409]
    |}]
;;

let json_raw =
  make
    ~meth:B.get
    ~path:(s "json-raw" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.json_raw ~description:"Arbitrary JSON" ()))
  @@ fun _request () -> Lwt.return (OK (`Assoc [ "ok", `Bool true ]))
;;

let unsafe =
  Unsafe.route ~meth:B.get ~path:"/unsafe" ~handler:(fun _request ->
    B.respond_string "unsafe")
;;

let%expect_test "unsafe routes stay out of OpenAPI and json_raw stays JSON" =
  let compiled = compile_exn [ group [ unsafe; json_raw ] ] in
  let document = Compiled.openapi compiled in
  let open Yojson.Safe.Util in
  let paths = document |> member "paths" in
  let unsafe_is_present = not (Yojson.Safe.equal (paths |> member "/unsafe") `Null) in
  let raw_schema =
    paths
    |> member "/json-raw"
    |> member "get"
    |> member "responses"
    |> member "200"
    |> member "content"
    |> member "application/json"
    |> member "schema"
  in
  Stdlib.Printf.printf
    "unsafe=%b schema=%s"
    unsafe_is_present
    (Yojson.Safe.to_string raw_schema);
  [%expect {| unsafe=false schema=true |}]
;;
