open! Base

type req =
  { request : Cohttp.Request.t
  ; body : string Lwt_stream.t Lazy.t
  ; params : (string * string) list
  }

type resp = Cohttp.Response.t * Cohttp_lwt.Body.t
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

type segment =
  | Static of string
  | Param of string

type route =
  { meth : Typed_endpoint.Method.t
  ; path : segment list
  ; handler : req -> resp io
  }

type app_builder = route list

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
  | None -> Static (Uri.pct_decode segment)
;;

let route meth path handler =
  let path =
    String.split path ~on:'/'
    |> List.filter ~f:(Fn.non String.is_empty)
    |> List.map ~f:parse_route_segment
  in
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
  Cohttp.Request.uri request.request
  |> Uri.query
  |> List.filter_map ~f:(fun (candidate, values) ->
    if String.equal candidate name then
      Some (String.concat values ~sep:",")
    else
      None)
;;

let header request name = Cohttp.Header.get (Cohttp.Request.headers request.request) name

let body_to_string ~max_bytes (request : req) =
  let buffer = Buffer.create (Int.max 0 (Int.min max_bytes 4096)) in
  let rec read size =
    let open Io.Let_syntax in
    let%bind chunk = Lwt_stream.get (Lazy.force request.body) in
    match chunk with
    | None -> return (Ok (Buffer.contents buffer))
    | Some chunk ->
      let length = String.length chunk in
      if length > max_bytes - size then
        return (Error `Too_large)
      else (
        Buffer.add_string buffer chunk;
        read (size + length))
  in
  if max_bytes < 0 then
    Io.return (Error `Too_large)
  else
    read 0
;;

let respond ?(status = `OK) ~headers ~body () =
  let status = Typed_endpoint.Status.code status |> Cohttp.Code.status_of_code in
  let encoding = Cohttp.Transfer.Fixed (Int64.of_int (String.length body)) in
  let response =
    Cohttp.Response.make ~status ~encoding ~headers:(Cohttp.Header.of_list headers) ()
  in
  Io.return (response, Cohttp_lwt.Body.of_string body)
;;

let respond_empty ?status () = respond ?status ~headers:[] ~body:"" ()

let respond_string ?status body =
  respond ?status ~headers:[ "content-type", "text/plain; charset=utf-8" ] ~body ()
;;

let respond_html ?status body =
  respond ?status ~headers:[ "content-type", "text/html; charset=utf-8" ] ~body ()
;;

let respond_json ?status ?(pretty = false) json =
  respond
    ?status
    ~headers:[ "content-type", "application/json" ]
    ~body:
      (if pretty then
         Yojson.Safe.pretty_to_string json
       else
         Yojson.Safe.to_string json)
    ()
;;

let dispatch routes ~request ~body =
  let path = Cohttp.Request.uri request |> Uri.path |> path_segments in
  let path_matches =
    List.filter_map routes ~f:(fun route ->
      Option.map (match_path route.path path []) ~f:(fun params -> route, params))
  in
  match
    List.find path_matches ~f:(fun (route, _params) ->
      Cohttp.Code.compare_method route.meth (Cohttp.Request.meth request) = 0)
  with
  | Some (route, params) ->
    route.handler { request; body = lazy (Cohttp_lwt.Body.to_stream body); params }
  | None when not (List.is_empty path_matches) ->
    let allow =
      path_matches
      |> List.map ~f:(fun (route, _params) -> Cohttp.Code.string_of_method route.meth)
      |> List.dedup_and_sort ~compare:String.compare
      |> String.concat ~sep:", "
    in
    respond
      ~status:`Method_not_allowed
      ~headers:[ "allow", allow; "content-type", "text/plain; charset=utf-8" ]
      ~body:"Method not allowed"
      ()
  | None -> respond_string ~status:`Not_found "Not found"
;;

let callback routes _connection request body = dispatch routes ~request ~body

module Request = struct
  let http request = request.request
  let header = header
end
