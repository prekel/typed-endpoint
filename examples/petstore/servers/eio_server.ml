open! Base
module Backend = Typed_endpoint_eio
module Database = Petstore_app.Database_memory.Make (Backend.Io)

module App =
  Petstore_app.Routes.Make (Backend) (Database) (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)

module Dsl = App.Endpoint.Dsl
module Access_log = Petstore_server_support.Access_log

let logger = Access_log.create ()

let request_id ~request ~next =
  let request_id =
    Access_log.ensure_request_id
      logger
      (Http.Header.get (Http.Request.headers request) "x-request-id")
  in
  let headers =
    Http.Header.replace (Http.Request.headers request) "x-request-id" request_id
  in
  let request : Http.Request.t = { request with headers } in
  let response = next request in
  Typed_endpoint_eio.Response.with_header response ~name:"x-request-id" ~value:request_id
;;

let access_log ~(route_info : Typed_endpoint.Route_info.t) ~request ~next =
  let event =
    Access_log.start_route
      logger
      ~method_:route_info.method_
      ~path_template:route_info.path_template
      ~request_id:(Typed_endpoint_eio.Request.header request "x-request-id")
  in
  try
    let response = next () in
    Access_log.finish
      event
      ~status:(Cohttp.Code.code_of_status (Typed_endpoint_eio.Response.status response));
    response
  with
  | exn ->
    Access_log.fail event exn;
    raise exn
;;

let () =
  let compiled =
    App.compile
      ~interceptors:[ access_log ]
      ~auth:(Petstore_app.Routes.auth_from_env ())
      ~database:(Database.create ())
      ()
  in
  let server =
    Dsl.Compiled.app compiled |> Typed_endpoint_eio.server ~middlewares:[ request_id ]
  in
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let socket =
    Eio.Net.listen
      ~sw
      ~backlog:128
      (Eio.Stdenv.net env)
      (`Tcp (Eio.Net.Ipaddr.V4.any, 8080))
  in
  Cohttp_eio.Server.run ~on_error:Stdlib.raise socket server
;;
