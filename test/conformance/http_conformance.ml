open! Base
open Typed_endpoint
module B = Typed_endpoint_testing
module E = Make (B)
module Check = Contract_test_support
open E

module Payload = struct
  type t = { value : int [@jsonschema.minimum 0] [@jsonschema.maximum 10] }
  [@@deriving yojson, jsonschema]

  let metadata =
    Metadata.v ~schema:t_jsonschema ~schema_name:"Payload" ~description:"Payload" ()
  ;;
end

let version =
  Header.required
    "X-Version"
    (Header.int ~schema_name:"Version" ~description:"Version" ())
;;

let mode = Header.optional "X-Mode" (Header.string ~description:"Mode" ())

let echo =
  post / "echo"
  |> documented
  |> accepts (Request.json (module Payload))
  |> returns
       (case
          `OK
          (Response.with_header
             version
             (Response.with_header mode (Response.json (module Payload)))))
  ==> fun ok () body ->
  match Request_body.read body with
  | Error error -> Request_body.reject error
  | Ok value -> respond ok (3, (None, value))
;;

let text path description =
  get / path
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description ()))
  ==> fun ok () () -> respond ok "hello"
;;

let empty =
  delete / "empty"
  |> documented
  |> accepts Request.empty
  |> returns (case `No_content (Response.empty ~description:"Deleted" ()))
  ==> fun ok () () -> respond ok ()
;;

let compiled =
  compile_exn
    [ Group.make_with_context
        ~context:(Context.return ())
        ~description:"Conformance"
        [ echo; text "text" "First"; text "other-text" "Second"; empty ]
    ]
;;

let doc = Compiled.openapi compiled
let send = B.Client.call (Compiled.app compiled)

let check path meth response =
  Check.response_exn
    ~document:doc
    ~path
    ~meth
    ~status:(B.Response.status response)
    ~headers:(B.Response.headers response)
    ~body:(B.Response.body response)
;;

let fails substring f =
  match Result.try_with f with
  | Ok () -> Stdlib.failwith ("expected contract failure: " ^ substring)
  | Error error -> assert (String.is_substring (Exn.to_string error) ~substring)
;;

let () =
  List.iter [ 0; 1; 5; 10 ] ~f:(fun value ->
    let json = Payload.to_yojson { value } in
    Check.request_json_exn
      ~document:doc
      ~path:"/echo"
      ~meth:"post"
      ~media_type:"application/json"
      json;
    let response =
      send
        ~headers:[ "content-type", "application/json" ]
        ~body:(Yojson.Safe.to_string json)
        `POST
        "/echo"
    in
    check "/echo" "post" response);
  List.iter [ "/text"; "/other-text" ] ~f:(fun path -> check path "get" (send `GET path));
  check "/empty" "delete" (send `DELETE "/empty");
  check
    "/echo"
    "post"
    (send ~headers:[ "content-type", "application/json" ] ~body:"{}" `POST "/echo");
  check
    "/echo"
    "post"
    (send ~headers:[ "content-type", "text/plain" ] ~body:"hello" `POST "/echo");
  let response =
    send
      ~headers:[ "content-type", "application/json" ]
      ~body:{|{"value":1}|}
      `POST
      "/echo"
  in
  let headers = B.Response.headers response in
  let body = B.Response.body response in
  let check ?(status = 200) ?(headers = headers) ?(body = body) () =
    Check.response_exn ~document:doc ~path:"/echo" ~meth:"post" ~status ~headers ~body
  in
  fails "undeclared response status" (fun () -> check ~status:201 ());
  fails "missing header" (fun () ->
    check ~headers:[ "content-type", "application/json" ] ());
  fails "header X-Version" (fun () ->
    check ~headers:[ "content-type", "application/json"; "x-version", "wrong" ] ());
  fails "undeclared Content-Type" (fun () ->
    check ~headers:[ "content-type", "text/plain"; "x-version", "3" ] ());
  fails "body schema" (fun () -> check ~body:{|{"value":-1}|} ());
  fails "invalid JSON" (fun () -> check ~body:"{" ());
  fails "expected empty body" (fun () ->
    Check.response_exn
      ~document:doc
      ~path:"/empty"
      ~meth:"delete"
      ~status:204
      ~headers:[]
      ~body:"unexpected");
  fails "Content-Type on empty" (fun () ->
    Check.response_exn
      ~document:doc
      ~path:"/empty"
      ~meth:"delete"
      ~status:204
      ~headers:[ "content-type", "application/json" ]
      ~body:"");
  fails "request schema" (fun () ->
    Check.request_json_exn
      ~document:doc
      ~path:"/echo"
      ~meth:"post"
      ~media_type:"application/json"
      (`Assoc [ "value", `Int (-1) ]));
  (* The codec still accepts this value: the conformance harness detects the
     response violation without introducing runtime validation into the DSL. *)
  let unconstrained =
    send
      ~headers:[ "content-type", "application/json" ]
      ~body:{|{"value":-1}|}
      `POST
      "/echo"
  in
  assert (Int.equal (B.Response.status unconstrained) 200);
  fails "body schema" (fun () ->
    Check.response_exn
      ~document:doc
      ~path:"/echo"
      ~meth:"post"
      ~status:200
      ~headers:(B.Response.headers unconstrained)
      ~body:(B.Response.body unconstrained))
;;
