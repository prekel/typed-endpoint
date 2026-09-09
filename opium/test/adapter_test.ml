open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_opium)
module Io = Endpoint.Io
open Io.Let_syntax
open Endpoint
open Dsl
open Staged

module Conformance = Typed_endpoint_testing.Backend_conformance.Make (struct
    module Backend = Typed_endpoint_opium

    let handler app =
      let app = app Opium.App.empty |> Opium.App.to_rock in
      let filters =
        Opium.Std.Rock.App.middlewares app |> List.map ~f:Opium.Std.Rock.Middleware.filter
      in
      Opium.Std.Rock.Filter.apply_all filters (Opium.Std.Rock.App.handler app)
    ;;

    let call app ?(headers = []) ?(body = "") meth target =
      let headers = Cohttp.Header.of_list headers in
      let request =
        Cohttp.Request.make ~meth ~headers (Uri.of_string target)
        |> Opium.Std.Request.create ~body:(Cohttp_lwt.Body.of_string body)
      in
      handler app request
    ;;

    let status response = Cohttp.Code.code_of_status (Opium.Std.Response.code response)

    let header response name =
      Cohttp.Header.get (Opium.Std.Response.headers response) name
    ;;

    let body response = Opium.Std.Response.body response |> Opium.Std.Body.to_string
  end)

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
  let ready =
    post / "echo"
    |> documented ()
    |> accepts (Request.text ~description:"Body" ())
    |> returns (ok (Response.text ~description:"Echo" ()))
  in
  handle ready @@ fun body -> return (OK body)
;;

let captured =
  Unsafe.route ~meth:B.get ~path:"/priority/:value" ~handler:(fun request ->
    B.respond_string ("capture:" ^ B.param request "value"))
;;

let fixed =
  Unsafe.route ~meth:B.get ~path:"/priority/fixed" ~handler:(fun _request ->
    B.respond_string "static")
;;

let app =
  compile_exn
    ~decode_error:decode_errors
    [ Group.v
        ~metadata:(Operation_metadata.v ~description:"Opium adapter test" ())
        [ route; captured; fixed ]
    ]
  |> Compiled.app
  |> fun build -> build Opium.App.empty |> Opium.App.to_rock
;;

let handler =
  let filters =
    Opium.Std.Rock.App.middlewares app |> List.map ~f:Opium.Std.Rock.Middleware.filter
  in
  Opium.Std.Rock.Filter.apply_all filters (Opium.Std.Rock.App.handler app)
;;

let () =
  let headers = Cohttp.Header.init_with "content-type" "text/plain" in
  let request =
    Cohttp.Request.make ~meth:`POST ~headers (Uri.of_string "/echo")
    |> Opium.Std.Request.create ~body:(Cohttp_lwt.Body.of_string "hello")
  in
  let response = Lwt_main.run (handler request) in
  assert (Int.equal (Cohttp.Code.code_of_status (Opium.Std.Response.code response)) 200);
  assert (
    Option.equal
      String.equal
      (Cohttp.Header.get (Opium.Std.Response.headers response) "content-type")
      (Some "text/plain; charset=utf-8"));
  let body =
    Lwt_main.run (Opium.Std.Response.body response |> Opium.Std.Body.to_string)
  in
  assert (String.equal body "hello");
  let request =
    Cohttp.Request.make ~meth:`GET (Uri.of_string "/priority/fixed")
    |> Opium.Std.Request.create ~body:Cohttp_lwt.Body.empty
  in
  let response = Lwt_main.run (handler request) in
  let body =
    Lwt_main.run (Opium.Std.Response.body response |> Opium.Std.Body.to_string)
  in
  assert (String.equal body "static");
  Lwt_main.run (Conformance.run ())
;;
