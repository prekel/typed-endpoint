open! Base
module Backend = Typed_endpoint_dream
module Database = Petstore_app.Database_memory.Make (Backend.Io)

module App =
  Petstore_app.Routes.Make (Backend) (Database) (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)

module Dsl = App.Endpoint.Dsl
module Access_log = Petstore_server_support.Access_log

let logger = Access_log.create ()

let request_id inner request =
  let request_id =
    Access_log.ensure_request_id logger (Dream.header request "x-request-id")
  in
  Dream.set_header request "x-request-id" request_id;
  let open Lwt.Let_syntax in
  let%map response = inner request in
  Dream.set_header response "x-request-id" request_id;
  response
;;

let access_log ~(route_info : Typed_endpoint.Route_info.t) ~request ~next =
  let event =
    Access_log.start_route
      logger
      ~method_:route_info.method_
      ~path_template:route_info.path_template
      ~request_id:(Dream.header request "x-request-id")
  in
  let open Lwt.Let_syntax in
  Lwt.catch
    (fun () ->
       let%map response = next () in
       Access_log.finish event ~status:(Dream.status_to_int (Dream.status response));
       response)
    (fun exn ->
       Access_log.fail event exn;
       Lwt.fail exn)
;;

let () =
  let compiled =
    App.compile
      ~interceptors:[ access_log ]
      ~auth:(Petstore_app.Routes.auth_from_env ())
      ~database:(Database.create ())
      ()
  in
  Dsl.Compiled.app compiled |> Typed_endpoint_dream.router |> request_id |> Dream.run
;;
