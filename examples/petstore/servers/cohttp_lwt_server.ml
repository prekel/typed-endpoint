open! Base
module Backend = Typed_endpoint_cohttp_lwt
module Database = Petstore_app.Database_memory.Make (Backend.Io)

module App =
  Petstore_app.Routes.Make (Backend) (Database) (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)
    (Database.Session_repository)
    (Petstore_server_support.Session_runtime)

module Endpoint = App.Endpoint
module Access_log = Petstore_server_support.Access_log
open Backend.Io.Let_syntax

let logger = Access_log.create ()

let request_id next connection (request : Cohttp.Request.t) body =
  let request_id =
    Access_log.ensure_request_id
      logger
      (Cohttp.Header.get (Cohttp.Request.headers request) "x-request-id")
  in
  let headers =
    Cohttp.Header.replace (Cohttp.Request.headers request) "x-request-id" request_id
  in
  let request = { request with headers } in
  let%map response, body = next connection request body in
  let headers =
    Cohttp.Header.replace (Cohttp.Response.headers response) "x-request-id" request_id
  in
  { response with headers }, body
;;

let access_log ~(route_info : Typed_endpoint.Route_info.t) ~request ~next =
  let event =
    Access_log.start_route
      logger
      ~method_:route_info.method_
      ~path_template:route_info.path_template
      ~request_id:(Backend.Request.header request "x-request-id")
  in
  Lwt.catch
    (fun () ->
       let%map ((response, _body) as result) = next () in
       Access_log.finish
         event
         ~status:(Cohttp.Code.code_of_status (Cohttp.Response.status response));
       result)
    (fun exn ->
       Access_log.fail event exn;
       Lwt.fail exn)
;;

let () =
  let compiled =
    App.compile
      ~interceptors:[ access_log ]
      ~auth:(Petstore_app.Routes.auth_from_env_exn ())
      ~database:(Database.create ())
      ()
  in
  let callback = Endpoint.Compiled.app compiled |> Backend.callback |> request_id in
  let server = Cohttp_lwt_unix.Server.make ~callback () in
  Lwt_main.run (Cohttp_lwt_unix.Server.create ~mode:(`TCP (`Port 8080)) server)
;;
