open! Base
open Typed_endpoint
module Backend = Typed_endpoint_cohttp_lwt
module Endpoint = Make (Backend)
open Endpoint
open Io.Let_syntax

let status (response, _body) =
  Cohttp.Response.status response |> Cohttp.Code.code_of_status
;;

let header (response, _body) name =
  Cohttp.Header.get (Cohttp.Response.headers response) name
;;

let response_body (_response, body) = Cohttp_lwt.Body.to_string body

let call app ?(headers = []) ?(body = Cohttp_lwt.Body.empty) meth target =
  let request =
    Cohttp.Request.make
      ~meth
      ~headers:(Cohttp.Header.of_list headers)
      (Uri.of_string target)
  in
  Backend.dispatch app ~request ~body
;;

module Conformance = Typed_endpoint_testing.Backend_conformance.Make (struct
    module Backend = Backend

    let call app ?headers ?(body = "") meth target =
      call app ?headers ~body:(Cohttp_lwt.Body.of_string body) meth target
    ;;

    let status = status
    let header = header
    let body = response_body
  end)

let echo =
  post / "echo"
  |> documented ~operation_id:"echo"
  |> accepts (Request.text ~max_body_bytes:4 ~description:"Bounded body" ())
  |> returns (case `OK (Response.text ~description:"Echo" ()))
  ==> fun ok () body ->
  let%bind result = Request_body.read body in
  let%bind cached = Request_body.read body in
  assert (Poly.equal result cached);
  match result with
  | Ok body ->
    let%bind () = Lwt.pause () in
    respond ok body
  | Error error -> Request_body.reject error
;;

let health =
  get / "health"
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Health" ()))
  ==> fun ok () () -> respond ok "ok"
;;

let authenticated =
  Guard.v
    ~status:`Unauthorized
    ~response:(Response.text ~description:"Unauthorized" ())
    ~check:(fun request ->
      let%map () = Lwt.pause () in
      match Backend.Request.header request "authorization" with
      | Some "Bearer secret" -> Ok "alice"
      | _ -> Error "unauthorized")
    ()
;;

let secured =
  get / "secured" /: arg "id" (Parameter.string ~description:"ID" ())
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"User and request" ()))
  ==> fun id ok (user, method_) () -> respond ok (user ^ ":" ^ method_ ^ ":" ^ id)
;;

let compiled =
  compile_exn
    [ Group.make_with_context
        ~context:(Context.return ())
        ~description:"Cohttp/Lwt adapter test"
        [ echo; health ]
    ; Group.make_with_context
        ~context:
          (Context.both
             authenticated
             (Dependency.of_request (fun request ->
                let%map () = Lwt.pause () in
                Backend.Request.http request
                |> Cohttp.Request.meth
                |> Cohttp.Code.string_of_method)))
        ~description:"Guard and request context"
        [ secured ]
    ]
;;

let app = Compiled.app compiled

let test_stream_limit () =
  let check_overflow chunks =
    let remaining = ref chunks in
    let reads = ref 0 in
    let stream =
      Lwt_stream.from (fun () ->
        Int.incr reads;
        match !remaining with
        | chunk :: rest ->
          remaining := rest;
          Lwt.return (Some chunk)
        | [] -> failwith "read beyond the chunk exceeding the body limit")
    in
    let%bind response =
      call
        app
        ~headers:[ "content-type", "text/plain" ]
        ~body:(Cohttp_lwt.Body.of_stream stream)
        `POST
        "/echo"
    in
    assert (Int.equal (status response) 413);
    assert (Int.equal !reads (List.length chunks));
    let%map body = response_body response in
    let error = Yojson.Safe.from_string body in
    assert (
      String.equal Yojson.Safe.Util.(error |> member "code" |> to_string) "body_too_large")
  in
  let%bind () = check_overflow [ "ab"; "cde" ] in
  let%bind () = check_overflow [ "oversized" ] in
  let%bind () = check_overflow [ ""; "ab"; ""; "cde" ] in
  let reads = ref 0 in
  let chunks = ref [ "ab"; ""; "cd" ] in
  let stream =
    Lwt_stream.from (fun () ->
      Int.incr reads;
      let next = List.hd !chunks in
      chunks := List.drop !chunks 1;
      Lwt.return next)
  in
  let%bind response =
    call
      app
      ~headers:[ "content-type", "text/plain" ]
      ~body:(Cohttp_lwt.Body.of_stream stream)
      `POST
      "/echo"
  in
  assert (Int.equal (status response) 200);
  assert (Int.equal !reads 4);
  let%map body = response_body response in
  assert (String.equal body "abcd")
;;

let test_lazy_body () =
  let untouched () =
    Cohttp_lwt.Body.of_stream
      (Lwt_stream.from (fun () -> failwith "body must stay unread"))
  in
  let%bind rejected = call app ~body:(untouched ()) `GET "/secured/42" in
  assert (Int.equal (status rejected) 401);
  let%bind accepted =
    call
      app
      ~headers:[ "authorization", "Bearer secret" ]
      ~body:(untouched ())
      `GET
      "/secured/value%252F"
  in
  assert (Int.equal (status accepted) 200);
  let%bind body = response_body accepted in
  assert (String.equal body "alice:GET:value%2F");
  let%bind unsupported =
    call
      app
      ~headers:[ "content-type", "application/json" ]
      ~body:(untouched ())
      `POST
      "/echo"
  in
  assert (Int.equal (status unsupported) 415);
  let%bind missing = call app ~body:(untouched ()) `POST "/missing" in
  assert (Int.equal (status missing) 404);
  let%map wrong_method = call app ~body:(untouched ()) `PUT "/echo" in
  assert (Int.equal (status wrong_method) 405)
;;

let test_encoded_static_segments () =
  List.fold [ "%3Aid"; "%2A"; "a%2Fb" ] ~init:(return ()) ~f:(fun checks segment ->
    let%bind () = checks in
    let route =
      get / "static" / segment
      |> documented
      |> accepts Request.empty
      |> returns (case `OK (Response.text ~description:"Static" ()))
      ==> fun ok () () -> respond ok "static"
    in
    let app =
      compile_exn
        [ Group.make_with_context
            ~context:(Context.return ())
            ~description:"Encoded static segment"
            [ route ]
        ]
      |> Compiled.app
    in
    let%bind matched = call app `GET ("/static/" ^ segment) in
    assert (Int.equal (status matched) 200);
    let%map missing = call app `GET "/static/different" in
    assert (Int.equal (status missing) 404))
;;

let test_native_response () =
  let%bind response =
    Backend.respond
      ~status:`Created
      ~headers:[ "set-cookie", "a=1"; "set-cookie", "b=2" ]
      ~body:"created"
      ()
  in
  assert (Int.equal (status response) 201);
  assert (
    List.equal
      String.equal
      (Cohttp.Header.get_multi (Cohttp.Response.headers (fst response)) "set-cookie")
      [ "a=1"; "b=2" ]);
  assert (Option.equal String.equal (header response "content-length") (Some "7"));
  assert (Option.is_none (header response "content-type"));
  let%bind html = Backend.respond_html "<p>ok</p>" in
  assert (
    Option.equal
      String.equal
      (header html "content-type")
      (Some "text/html; charset=utf-8"));
  let%map empty = Backend.respond_empty ~status:`No_content () in
  assert (Int.equal (status empty) 204);
  assert (Option.is_none (header empty "content-type"))
;;

let test_cancellation () =
  let started, start = Lwt.wait () in
  let pending, _resolve = Lwt.task () in
  let routes =
    Backend.route `GET "/pending" (fun _request ->
      Lwt.wakeup_later start ();
      let%bind () = pending in
      Backend.respond_empty ())
  in
  let response = call routes `GET "/pending" in
  let%bind () = started in
  Lwt.cancel response;
  assert (Poly.equal (Lwt.state pending) (Lwt.Fail Lwt.Canceled));
  Lwt.catch
    (fun () ->
       let%map _response = response in
       failwith "cancelled dispatch returned a response")
    (function
      | Lwt.Canceled -> return ()
      | exn -> Lwt.fail exn)
;;

let test_server () =
  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  let%bind () = Lwt_unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_loopback, 0)) in
  Lwt_unix.listen socket 8;
  let address = Lwt_unix.getsockname socket in
  let stop, stop_server = Lwt.wait () in
  let callback connection request body =
    let headers =
      Cohttp.Header.replace (Cohttp.Request.headers request) "x-request-id" "generated"
    in
    let request = { request with headers } in
    let%map response, body = Backend.callback app connection request body in
    let headers =
      Cohttp.Header.replace (Cohttp.Response.headers response) "x-request-id" "generated"
    in
    { response with headers }, body
  in
  let server =
    Cohttp_lwt_unix.Server.make ~callback ()
    |> Cohttp_lwt_unix.Server.create ~stop ~mode:(`TCP (`Socket socket))
  in
  Lwt.finalize
    (fun () ->
       let%bind input, output = Lwt_io.open_connection address in
       Lwt.finalize
         (fun () ->
            let%bind () =
              Lwt_io.write
                output
                "POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nab\r\n3\r\ncde\r\n4\r\ntail\r\n0\r\n\r\nPOST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Type: text/plain\r\nContent-Length: 4\r\n\r\ndataGET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
            in
            let%bind () = Lwt_io.flush output in
            let%map responses = Lwt_io.read input in
            assert (String.is_substring responses ~substring:"HTTP/1.1 413");
            assert (
              Int.equal
                (List.length
                   (String.substr_index_all
                      responses
                      ~pattern:"HTTP/1.1 200"
                      ~may_overlap:false))
                2);
            assert (String.is_substring responses ~substring:"\r\n\r\ndataHTTP/1.1");
            assert (String.is_substring responses ~substring:"x-request-id: generated");
            assert (String.is_suffix responses ~suffix:"\r\n\r\nok"))
         (fun () ->
            let%bind () = Lwt_io.close output in
            Lwt_io.close input))
    (fun () ->
       Lwt.wakeup_later stop_server ();
       server)
;;

let () =
  let tests () =
    let%bind () = Conformance.run () in
    let%bind () = test_stream_limit () in
    let%bind () = test_lazy_body () in
    let%bind () = test_encoded_static_segments () in
    let%bind () = test_native_response () in
    let%bind () = test_cancellation () in
    test_server ()
  in
  Lwt_main.run
    (Lwt.pick
       [ tests ()
       ; (let%map () = Lwt_unix.sleep 10. in
          failwith "Cohttp/Lwt adapter tests timed out")
       ])
;;
