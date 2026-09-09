open! Base

type req =
  { request : Http.Request.t
  ; uri : Uri.t
  ; body : [ `String of string | `Stream of Cohttp_eio.Body.t ]
  ; params : (string * string) list
  }

type resp =
  { status : Http.Status.t
  ; headers : Http.Header.t
  ; body : string
  }

type 'a io = 'a
type body_read_error = [ `Too_large ]
type middleware = request:Http.Request.t -> next:(Http.Request.t -> resp) -> resp

module Io = struct
  type 'a t = 'a io

  include Base.Monad.Make (struct
      type nonrec 'a t = 'a io

      let return value = value
      let bind value ~f = f value
      let map = `Custom (fun value ~f -> f value)
    end)
end

include Cohttp.Code

type segment =
  | Static of string
  | Param of string

type route =
  { meth : meth
  ; path : segment list
  ; handler : req -> resp
  }

type app_builder = route list

let get : meth = `GET
let post : meth = `POST
let put : meth = `PUT
let delete : meth = `DELETE
let patch : meth = `PATCH
let empty = []
let combine = List.append

let path_segments path =
  String.split path ~on:'/'
  |> List.filter ~f:(Fn.non String.is_empty)
  |> List.map ~f:Uri.pct_decode
;;

let parse_route_segment segment =
  match String.chop_prefix segment ~prefix:":" with
  | Some name -> Param name
  | None -> Static segment
;;

let route meth path handler =
  let path = path_segments path |> List.map ~f:parse_route_segment in
  [ { meth; path; handler } ]
;;

let rec match_path pattern path params =
  match pattern, path with
  | [], [] -> Some (List.rev params)
  | Static expected :: pattern, actual :: path when String.equal expected actual ->
    match_path pattern path params
  | Param name :: pattern, value :: path ->
    match_path pattern path ((name, value) :: params)
  | _ -> None
;;

let param (request : req) name =
  List.Assoc.find_exn request.params name ~equal:String.equal
;;

let query (request : req) name =
  Uri.query request.uri
  |> List.filter_map ~f:(fun (candidate, values) ->
    if String.equal candidate name then
      Some (String.concat values ~sep:",")
    else
      None)
;;

let header request name = Http.Header.get (Http.Request.headers request.request) name

let body_to_string ~max_bytes (request : req) =
  match request.body with
  | `String body ->
    if String.length body > max_bytes then
      Error `Too_large
    else
      Ok body
  | `Stream body ->
    let max_size =
      if Int.equal max_bytes Int.max_value then
        max_bytes
      else
        max_bytes + 1
    in
    (match Eio.Buf_read.parse ~max_size Eio.Buf_read.take_all body with
     | Ok body -> Ok body
     | Error _ -> Error `Too_large)
;;

let respond ?(status = `OK) ~headers ~body () =
  { status; headers = Http.Header.of_list headers; body }
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

let dispatch_with_body routes ~request ~body =
  let uri = Uri.of_string (Http.Request.resource request) in
  let path = Uri.path uri |> path_segments in
  let path_matches =
    List.filter_map routes ~f:(fun route ->
      Option.map (match_path route.path path []) ~f:(fun params -> route, params))
  in
  match
    List.find path_matches ~f:(fun (route, _params) ->
      Http.Method.compare route.meth (Http.Request.meth request) = 0)
  with
  | Some (route, params) -> route.handler { request; uri; body; params }
  | None when not (List.is_empty path_matches) ->
    let allow =
      path_matches
      |> List.map ~f:(fun (route, _params) -> Http.Method.to_string route.meth)
      |> List.dedup_and_sort ~compare:String.compare
      |> String.concat ~sep:", "
    in
    let headers = Http.Header.init_with "allow" allow in
    let headers = Http.Header.add headers "content-type" "text/plain; charset=utf-8" in
    { status = `Method_not_allowed; headers; body = "Method not allowed" }
  | None ->
    respond
      ~status:`Not_found
      ~headers:[ "content-type", "text/plain; charset=utf-8" ]
      ~body:"Not found"
      ()
;;

let apply_middlewares middlewares ~request ~next =
  let next =
    List.fold_right middlewares ~init:next ~f:(fun middleware next request ->
      middleware ~request ~next)
  in
  next request
;;

let dispatch ?(middlewares = []) routes ~request ~body =
  apply_middlewares middlewares ~request ~next:(fun request ->
    dispatch_with_body routes ~request ~body:(`String body))
;;

let response_writer response =
  Cohttp_eio.Server.respond_string
    ~headers:response.headers
    ~status:response.status
    ~body:response.body
    ()
;;

let server ?(middlewares = []) routes =
  Cohttp_eio.Server.make_response_action
    ~callback:(fun _connection request body ->
      `Response
        (apply_middlewares middlewares ~request ~next:(fun request ->
           dispatch_with_body routes ~request ~body:(`Stream body))
         |> response_writer))
    ()
;;

module Request = struct
  let http request = request.request
  let header request name = Http.Header.get (Http.Request.headers request.request) name
end

module Response = struct
  let status response = response.status
  let headers response = response.headers
  let body response = response.body

  let with_header response ~name ~value =
    { response with headers = Http.Header.replace response.headers name value }
  ;;
end
