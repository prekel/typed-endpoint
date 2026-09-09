open! Base
module Backend = Typed_endpoint_opium
module Database = Petstore_app.Database_memory.Make (Backend.Io)

module App =
  Petstore_app.Routes.Make (Backend) (Database) (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)

module Dsl = App.Endpoint.Dsl
module Access_log = Petstore_server_support.Access_log

let logger = Access_log.create ()

let request_id =
  Opium.Std.Rock.Middleware.create
    ~name:"petstore-request-id"
    ~filter:(fun next (request : Opium.Std.Request.t) ->
      let request_id =
        Access_log.ensure_request_id
          logger
          (Cohttp.Header.get (Opium.Std.Request.headers request) "x-request-id")
      in
      let http_request = request.request in
      let http_request =
        { http_request with
          headers = Cohttp.Header.replace http_request.headers "x-request-id" request_id
        }
      in
      let request = { request with request = http_request } in
      let open Lwt.Let_syntax in
      let%map response = next request in
      { response with
        headers = Cohttp.Header.replace response.headers "x-request-id" request_id
      })
;;

let access_log
      ~(route_info : Typed_endpoint.Route_info.t)
      ~(request : Opium.Std.Request.t)
      ~(next : unit -> Opium.Std.Response.t Lwt.t)
  =
  let event =
    Access_log.start_route
      logger
      ~method_:route_info.method_
      ~path_template:route_info.path_template
      ~request_id:(Cohttp.Header.get (Opium.Std.Request.headers request) "x-request-id")
  in
  let open Lwt.Let_syntax in
  Lwt.catch
    (fun () ->
       let%map response = next () in
       Access_log.finish event ~status:(Cohttp.Code.code_of_status response.code);
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
  Opium.App.empty
  |> Dsl.Compiled.app compiled
  |> Opium.App.middleware request_id
  |> Opium.App.port 8080
  |> Opium.App.run_command
;;
