open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_dream)
open Endpoint
open Endpoint.Dsl

module String_param = struct
  type t = string

  let of_string value = Ok value

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:(`Assoc [ "type", `String "string" ])
      ~description:"String parameter"
      ()
  ;;
end

module Error_payload = struct
  type t = { message : string }

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (`Assoc
            [ "type", `String "object"
            ; "properties", `Assoc [ "message", `Assoc [ "type", `String "string" ] ]
            ])
      ~description:"Error"
      ()
  ;;

  let to_yojson error = `Assoc [ "message", `String error.message ]
end

let decode_errors =
  Decode_error_response.json
    ~payload:(module Error_payload)
    ~map:(fun _error -> Error_payload.{ message = "decode error" })
;;

let route =
  make_with
    ~context:Context.request
    ~meth:B.post
    ~path:(s "items" / param "id" (module String_param) /? nil)
    ~request:(Request.text ~description:"Body" ())
    ~responses:(ok (Response.text ~description:"OK" ()))
  @@ fun id request body ->
  let query = Dream.query request "q" |> Option.value ~default:"none" in
  Lwt.return (OK (String.concat ~sep:":" [ id; query; body ]))
;;

let custom =
  Unsafe.route ~meth:(`Other "PROPFIND") ~path:"/custom" ~handler:(fun _request ->
    Dream.respond "custom")
;;

let handler =
  compile_exn
    ~decode_error:decode_errors
    [ Group.v
        ~prefix:[ "v1" ]
        ~metadata:(Operation_metadata.v ~description:"Dream test" ())
        [ route; custom ]
    ]
  |> Compiled.app
  |> Typed_endpoint_dream.router
;;

let () =
  let request =
    Dream.request
      ~method_:`POST
      ~target:"/v1/items/42?q=hello"
      ~headers:[ "content-type", "text/plain" ]
      "body"
  in
  let response = Dream.test handler request in
  assert (Dream.status_to_int (Dream.status response) = 200);
  assert (String.equal (Lwt_main.run (Dream.body response)) "42:hello:body");
  let request = Dream.request ~method_:(`Method "PROPFIND") ~target:"/v1/custom" "" in
  let response = Dream.test handler request in
  assert (Dream.status_to_int (Dream.status response) = 200);
  assert (String.equal (Lwt_main.run (Dream.body response)) "custom")
;;
