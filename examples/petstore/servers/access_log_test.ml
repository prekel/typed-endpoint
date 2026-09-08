open! Base
module Access_log = Petstore_server_support.Access_log

let field name = function
  | `Assoc fields -> List.Assoc.find_exn fields name ~equal:String.equal
  | _ -> failwith "access log event must be an object"
;;

let last_line lines =
  match List.last lines with
  | Some line -> line
  | None -> failwith "expected an access log line"
;;

let () =
  let lines = ref [] in
  let times = ref [ 1_700_000_000.; 1_700_000_000.125 ] in
  let now () =
    match !times with
    | time :: remaining ->
      times := remaining;
      time
    | [] -> failwith "unexpected clock read"
  in
  let logger =
    Access_log.create
      ~now
      ~write:(fun line -> lines := !lines @ [ line ])
      ~fresh_id:(fun () -> "generated")
      ()
  in
  let request =
    Access_log.start
      logger
      ~method_:"GET"
      ~target:"/pet/42?api_key=secret&token=also-secret"
      ~request_id:(Some "gateway-42")
  in
  assert (String.equal (Access_log.request_id request) "gateway-42");
  Access_log.finish request ~status:200;
  let event = last_line !lines |> Yojson.Safe.from_string in
  assert (Yojson.Safe.equal (field "event" event) (`String "http_request"));
  assert (Yojson.Safe.equal (field "method" event) (`String "GET"));
  assert (Yojson.Safe.equal (field "path" event) (`String "/pet/42"));
  assert (Yojson.Safe.equal (field "status" event) (`Int 200));
  assert (Yojson.Safe.equal (field "request_id" event) (`String "gateway-42"));
  assert (Yojson.Safe.equal (field "duration_ms" event) (`Float 125.));
  assert (not (String.is_substring (last_line !lines) ~substring:"secret"));
  let invalid_logger =
    Access_log.create ~fresh_id:(fun () -> "generated") ~write:(fun _ -> ()) ()
  in
  let invalid_request =
    Access_log.start
      invalid_logger
      ~method_:"GET"
      ~target:"/health"
      ~request_id:(Some "not\nvalid")
  in
  assert (String.equal (Access_log.request_id invalid_request) "generated");
  let error_lines = ref [] in
  let error_logger =
    Access_log.create
      ~now:(fun () -> 1_700_000_000.)
      ~write:(fun line -> error_lines := !error_lines @ [ line ])
      ()
  in
  let error_request =
    Access_log.start error_logger ~method_:"POST" ~target:"/pet" ~request_id:None
  in
  Access_log.fail error_request (Failure "database connection failed");
  let error_event = last_line !error_lines |> Yojson.Safe.from_string in
  assert (Yojson.Safe.equal (field "level" error_event) (`String "error"));
  (match field "error" error_event with
   | `String message ->
     assert (String.is_substring message ~substring:"database connection failed")
   | _ -> assert false);
  let broken_logger =
    Access_log.create ~write:(fun _ -> raise (Failure "sink failed")) ()
  in
  let broken_request =
    Access_log.start broken_logger ~method_:"GET" ~target:"/health" ~request_id:None
  in
  Access_log.finish broken_request ~status:200
;;
