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

let access_log inner request =
  let event =
    Access_log.start
      logger
      ~method_:(Dream.method_to_string (Dream.method_ request))
      ~target:(Dream.target request)
      ~request_id:(Dream.header request "x-request-id")
  in
  let open Lwt.Let_syntax in
  Lwt.catch
    (fun () ->
       let%map response = inner request in
       Dream.set_header response "x-request-id" (Access_log.request_id event);
       Access_log.finish event ~status:(Dream.status_to_int (Dream.status response));
       response)
    (fun exn ->
       Access_log.fail event exn;
       Lwt.fail exn)
;;

let () =
  let compiled =
    App.compile
      ~auth:(Petstore_app.Routes.auth_from_env ())
      ~database:(Database.create ())
  in
  Dsl.Compiled.app compiled |> Typed_endpoint_dream.router |> access_log |> Dream.run
;;
