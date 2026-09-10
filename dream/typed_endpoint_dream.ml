open! Base

type req = Dream.request
type resp = Dream.response
type 'a io = 'a Lwt.t

module Io = struct
  type 'a t = 'a io

  include Base.Monad.Make (struct
      type nonrec 'a t = 'a io

      let return = Lwt.return
      let bind value ~f = Lwt.bind value f
      let map = `Custom (fun value ~f -> Lwt.map f value)
    end)
end

type route =
  { meth : Typed_endpoint.Method.t
  ; path : string
  ; handler : req -> resp io
  }

type app_builder = route list

let empty = []
let combine = List.append
let route meth path handler = [ { meth; path; handler } ]
let param = Dream.param
let query = Dream.queries
let header request name = Dream.header request name

let body_to_string ~max_bytes request =
  let stream = Dream.body_stream request in
  let buffer = Buffer.create (Int.min max_bytes 4096) in
  let rec read size =
    let open Io.Let_syntax in
    let%bind chunk = Dream.read stream in
    match chunk with
    | None -> return (Ok (Buffer.contents buffer))
    | Some chunk ->
      let size = size + String.length chunk in
      if size > max_bytes then
        return (Error `Too_large)
      else (
        Buffer.add_string buffer chunk;
        read size)
  in
  read 0
;;

let respond ?status ~headers ~body () =
  let code = Option.map status ~f:Typed_endpoint.Status.code in
  Dream.respond ~headers ?code body
;;

let respond_empty ?status () = respond ?status ~headers:[] ~body:"" ()

let respond_string ?status body =
  respond ?status ~headers:[ "content-type", "text/plain; charset=utf-8" ] ~body ()
;;

let respond_html ?status body =
  respond ?status ~headers:[ "content-type", "text/html; charset=utf-8" ] ~body ()
;;

let respond_json ?status json =
  respond
    ?status
    ~headers:[ "content-type", "application/json" ]
    ~body:(Yojson.Safe.to_string json)
    ()
;;

let dream_method : Typed_endpoint.Method.t -> Dream.method_ = function
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
      | None ->
        let allow =
          routes
          |> List.map ~f:(fun route -> Cohttp.Code.string_of_method route.meth)
          |> List.dedup_and_sort ~compare:String.compare
          |> String.concat ~sep:", "
        in
        Dream.respond
          ~code:405
          ~headers:[ "allow", allow; "content-type", "text/plain; charset=utf-8" ]
          "Method not allowed"))
  |> Dream.router
;;
