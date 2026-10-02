open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_dream)
module Io = Endpoint.Io
open Io.Let_syntax
open Endpoint

module Conformance = Typed_endpoint_testing.Backend_conformance.Make (struct
    module Backend = Typed_endpoint_dream

    let dream_method : Method.t -> Dream.method_ = function
      | `GET -> `GET
      | `POST -> `POST
      | `PUT -> `PUT
      | `DELETE -> `DELETE
      | `PATCH -> `PATCH
      | `HEAD -> `HEAD
      | `CONNECT -> `CONNECT
      | `OPTIONS -> `OPTIONS
      | `TRACE -> `TRACE
      | `Other method_ -> `Method method_
    ;;

    let call app ?(headers = []) ?(body = "") meth target =
      let request = Dream.request ~method_:(dream_method meth) ~target ~headers body in
      Dream.test (Typed_endpoint_dream.router app) request |> Lwt.return
    ;;

    let status response = Dream.status_to_int (Dream.status response)
    let header response name = Dream.header response name
    let body = Dream.body
  end)

module String_param = struct
  type t = string

  let of_string value = Ok value

  let metadata : t Metadata.t =
    Metadata.v ~schema:(Json_schema.string_exn ()) ~description:"String parameter" ()
  ;;
end

module Error_payload = struct
  type t = { message : string }

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (Json_schema.Unsafe.of_yojson
           (`Assoc
               [ "type", `String "object"
               ; "properties", `Assoc [ "message", `Assoc [ "type", `String "string" ] ]
               ]))
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
  post / "items" /: arg "id" (module String_param)
  |> documented
  |> accepts (Request.text ~description:"Body" ())
  |> returns (case `OK (Response.text ~description:"OK" ()))
  |> handle_with ~context:Context.request @@ fun id ok request body ->
     let%bind result = Request_body.read body in
     match result with
     | Error error -> Request_body.reject error
     | Ok body ->
       let query = Dream.query request "q" |> Option.value ~default:"none" in
       respond ok (String.concat ~sep:":" [ id; query; body ])
;;

let custom =
  Unsafe.route ~meth:(`Other "PROPFIND") ~path:"/custom" ~handler:(fun _request ->
    Dream.respond "custom")
;;

let captured =
  Unsafe.route ~meth:`GET ~path:"/priority/:value" ~handler:(fun request ->
    Dream.respond ("capture:" ^ Dream.param request "value"))
;;

let fixed =
  Unsafe.route ~meth:`GET ~path:"/priority/fixed" ~handler:(fun _request ->
    Dream.respond "static")
;;

let handler =
  compile_exn
    ~decode_error:decode_errors
    [ Group.make
        ~prefix:[ "v1" ]
        ~description:"Dream test"
        [ route; custom; captured; fixed ]
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
  assert (
    Option.equal
      String.equal
      (Dream.header response "content-type")
      (Some "text/plain; charset=utf-8"));
  assert (String.equal (Lwt_main.run (Dream.body response)) "42:hello:body");
  let request = Dream.request ~method_:`GET ~target:"/v1/items/42" "" in
  let response = Dream.test handler request in
  assert (Dream.status_to_int (Dream.status response) = 405);
  assert (Option.equal String.equal (Dream.header response "allow") (Some "POST"));
  let request = Dream.request ~method_:`GET ~target:"/v1/priority/fixed" "" in
  let response = Dream.test handler request in
  assert (String.equal (Lwt_main.run (Dream.body response)) "static");
  let request = Dream.request ~method_:(`Method "PROPFIND") ~target:"/v1/custom" "" in
  let response = Dream.test handler request in
  assert (Dream.status_to_int (Dream.status response) = 200);
  assert (String.equal (Lwt_main.run (Dream.body response)) "custom");
  Lwt_main.run (Conformance.run ())
;;
