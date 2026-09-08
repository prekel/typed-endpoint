open! Base
module Backend = Typed_endpoint_dream
module Pet_repository = Petstore_app.Pet_repository_memory.Make (Backend.Io)
module Order_repository = Petstore_app.Order_repository_memory.Make (Backend.Io)
module User_repository = Petstore_app.User_repository_memory.Make (Backend.Io)

module App =
  Petstore_app.Routes.Make (Backend) (Pet_repository) (Order_repository) (User_repository)

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
      ~pet_repository:(Pet_repository.create ())
      ~order_repository:(Order_repository.create ())
      ~user_repository:(User_repository.create ())
  in
  Dsl.Compiled.app compiled |> Typed_endpoint_dream.router |> access_log |> Dream.run
;;
