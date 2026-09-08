open! Base
module App = Petstore_app.Routes.Make (Typed_endpoint_opium)
module Dsl = App.Endpoint.Dsl
module Access_log = Petstore_server_support.Access_log

let logger = Access_log.create ()

let access_log =
  Opium.Std.Rock.Middleware.create
    ~name:"petstore-access-log"
    ~filter:(fun next request ->
      let event =
        Access_log.start
          logger
          ~method_:(Cohttp.Code.string_of_method (Opium.Std.Request.meth request))
          ~target:(Uri.to_string (Opium.Std.Request.uri request))
          ~request_id:
            (Cohttp.Header.get (Opium.Std.Request.headers request) "x-request-id")
      in
      let open Lwt.Let_syntax in
      Lwt.catch
        (fun () ->
           let%map response = next request in
           let response =
             { response with
               headers =
                 Cohttp.Header.replace
                   response.headers
                   "x-request-id"
                   (Access_log.request_id event)
             }
           in
           Access_log.finish event ~status:(Cohttp.Code.code_of_status response.code);
           response)
        (fun exn ->
           Access_log.fail event exn;
           Lwt.fail exn))
;;

let () =
  let services = App.Services.create () in
  let compiled = App.compile ~auth:(Petstore_app.Routes.auth_from_env ()) services in
  Opium.App.empty
  |> Dsl.Compiled.app compiled
  |> Opium.App.middleware access_log
  |> Opium.App.port 8080
  |> Opium.App.run_command
;;
