open! Base
module Backend = Typed_endpoint_eio
module Pet_repository = Petstore_app.Pet_repository_memory.Make (Backend.Io)
module Order_repository = Petstore_app.Order_repository_memory.Make (Backend.Io)
module User_repository = Petstore_app.User_repository_memory.Make (Backend.Io)

module App =
  Petstore_app.Routes.Make (Backend) (Pet_repository) (Order_repository) (User_repository)

module Dsl = App.Endpoint.Dsl
module Access_log = Petstore_server_support.Access_log

let logger = Access_log.create ()

let access_log ~request ~next =
  let event =
    Access_log.start
      logger
      ~method_:(Http.Method.to_string (Http.Request.meth request))
      ~target:(Http.Request.resource request)
      ~request_id:(Http.Header.get (Http.Request.headers request) "x-request-id")
  in
  try
    let response = next () in
    let response =
      Typed_endpoint_eio.Response.with_header
        response
        ~name:"x-request-id"
        ~value:(Access_log.request_id event)
    in
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
      ~auth:(Petstore_app.Routes.auth_from_env ())
      ~pet_repository:(Pet_repository.create ())
      ~order_repository:(Order_repository.create ())
      ~user_repository:(User_repository.create ())
  in
  let server =
    Dsl.Compiled.app compiled |> Typed_endpoint_eio.server ~middlewares:[ access_log ]
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
