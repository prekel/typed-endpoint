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

module Endpoint = Make (Test_backend) (Wrapper.Identity)
open Endpoint
open Endpoint.D

module Int_param = struct
  type t = int [@@deriving jsonschema]

  let of_string value =
    try Ok (Int.of_string value) with
    | _ -> Error "not an integer"
  ;;

  let metadata = Metadata.v ~description:"Integer parameter" ()
end

let group routes = Group.v ~metadata:(Metadata.v ~description:"Test routes" ()) routes

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

let missing_parse_error_mapper =
  make
    ~meth:B.get
    ~path:(s "users" / param "id" (module Int_param) /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"OK" ()))
  @@ fun id _request () -> Lwt.return (OK (Int.to_string id))
;;

let%expect_test "fallible input requires an explicit parse-error mapper" =
  print_compile_result [ group [ missing_parse_error_mapper ] ];
  [%expect {| missing parse-error mapper: get /users/:id |}]
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
