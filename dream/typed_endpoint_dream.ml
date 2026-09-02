open! Base

type req = Dream.request
type resp = Dream.response
type 'a io = 'a Lwt.t

include Cohttp.Code

type route =
  { meth : meth
  ; path : string
  ; handler : req -> resp io
  }

type app_builder = route list

let get : meth = `GET
let post : meth = `POST
let put : meth = `PUT
let delete : meth = `DELETE
let patch : meth = `PATCH
let return = Lwt.return
let bind value ~f = Lwt.bind value f
let empty = []
let combine = List.append
let route meth path handler = [ { meth; path; handler } ]
let param = Dream.param
let query = Dream.query
let body_to_string = Dream.body

let respond_string ?status body =
  let code = Option.map status ~f:code_of_status in
  Dream.respond ?code body
;;

let respond_json ?status json =
  let code = Option.map status ~f:code_of_status in
  Dream.json ?code (Yojson.Safe.to_string json)
;;

let dream_method : meth -> Dream.method_ = function
  | `GET -> `GET
  | `POST -> `POST
  | `PUT -> `PUT
  | `DELETE -> `DELETE
  | `PATCH -> `PATCH
  | `HEAD -> `HEAD
  | `CONNECT -> `CONNECT
  | `OPTIONS -> `OPTIONS
  | `TRACE -> `TRACE
  | `Other method_ -> `Method method_
;;

let rec add_route_by_path grouped route =
  match grouped with
  | [] -> [ route.path, [ route ] ]
  | (path, routes) :: tail when String.equal path route.path ->
    (path, routes @ [ route ]) :: tail
  | group :: tail -> group :: add_route_by_path tail route
;;

let router routes =
  List.fold routes ~init:[] ~f:add_route_by_path
  |> List.map ~f:(fun (path, routes) ->
    Dream.any path (fun request ->
      match
        List.find routes ~f:(fun route ->
          Dream.methods_equal (Dream.method_ request) (dream_method route.meth))
      with
      | Some route -> route.handler request
      | None -> Dream.respond ~code:405 "Method not allowed"))
  |> Dream.router
;;
