open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
open Endpoint

let int_arg argv index ~default =
  Array.get argv index |> Int.of_string_opt |> Option.value ~default
;;

let () =
  let argv = Sys.get_argv () in
  let route_count =
    if Array.length argv > 1 then
      int_arg argv 1 ~default:1_000
    else
      1_000
  in
  let iterations =
    if Array.length argv > 2 then
      int_arg argv 2 ~default:100_000
    else
      100_000
  in
  let routes =
    List.init route_count ~f:(fun index ->
      Unsafe.route
        ~meth:`GET
        ~path:("/bench/" ^ Int.to_string index)
        ~handler:(fun _request -> Typed_endpoint_testing.respond_string "ok"))
  in
  let app =
    compile_exn [ Group.make ~description:"Router benchmark" routes ] |> Compiled.app
  in
  let target = "/bench/" ^ Int.to_string (route_count - 1) in
  let started = Unix.gettimeofday () in
  for _ = 1 to iterations do
    ignore
      (Typed_endpoint_testing.Client.call app `GET target
       : Typed_endpoint_testing.response)
  done;
  let elapsed = Unix.gettimeofday () -. started in
  Stdlib.Printf.printf
    "routes=%d requests=%d elapsed=%.6fs us/request=%.3f\n%!"
    route_count
    iterations
    elapsed
    (elapsed *. 1_000_000. /. Float.of_int iterations)
;;
