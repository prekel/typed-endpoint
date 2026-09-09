open! Base

type req = Opium.Std.Request.t
type resp = Opium.Std.Response.t
type 'a io = 'a Lwt.t
type body_read_error = [ `Too_large ]

module Io = struct
  type 'a t = 'a io

  include Base.Monad.Make (struct
      type nonrec 'a t = 'a io

      let return = Lwt.return
      let bind value ~f = Lwt.bind value f
      let map = `Custom (fun value ~f -> Lwt.map f value)
    end)
end

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
let empty = []
let combine = List.append

let method_not_allowed_middleware routes =
  let routes =
    List.map routes ~f:(fun route -> route, Opium.Std.Route.of_string route.path)
  in
  Opium.Std.Rock.Middleware.create
    ~name:"typed-endpoint-method-not-allowed"
    ~filter:(fun next request ->
      let open Io.Let_syntax in
      let%map response = next request in
      let status = Cohttp.Code.code_of_status response.code in
      let path = Opium.Std.Request.uri request |> Uri.path in
      let path_matches =
        List.filter routes ~f:(fun (_route, pattern) ->
          Opium.Std.Route.match_url pattern path |> Option.is_some)
      in
      let method_matches =
        List.exists path_matches ~f:(fun (route, _pattern) ->
          Int.equal
            (Cohttp.Code.compare_method route.meth (Opium.Std.Request.meth request))
            0)
      in
      if
        (not (List.is_empty path_matches))
        && (not method_matches)
        && (Int.equal status 404 || Int.equal status 405)
      then (
        let methods =
          Cohttp.Header.get response.headers "allow"
          |> Option.value_map ~default:[] ~f:(fun value ->
            String.split value ~on:',' |> List.map ~f:String.strip)
          |> List.append
               (List.map path_matches ~f:(fun (route, _pattern) ->
                  Cohttp.Code.string_of_method route.meth))
          |> List.dedup_and_sort ~compare:String.compare
        in
        let headers =
          Cohttp.Header.replace response.headers "allow" (String.concat methods ~sep:", ")
        in
        let headers =
          Cohttp.Header.replace headers "content-type" "text/plain; charset=utf-8"
        in
        { response with
          code = `Method_not_allowed
        ; headers
        ; body = Cohttp_lwt.Body.of_string "Method not allowed"
        })
      else
        response)
;;

let route (m : meth) (path : string) (h : req -> resp Lwt.t) : app_builder =
  [ { meth = m; path; handler = h } ]
;;

let register route app =
  let register =
    match route.meth with
    | `GET -> Opium.Std.get route.path route.handler
    | `POST -> Opium.Std.post route.path route.handler
    | `PUT -> Opium.Std.put route.path route.handler
    | `DELETE -> Opium.Std.delete route.path route.handler
    | `PATCH -> Opium.Std.App.patch route.path route.handler
    | meth -> Opium.Std.App.action meth route.path route.handler
  in
  register app
;;

let mount routes app =
  let app = List.fold_right routes ~init:app ~f:register in
  Opium.Std.App.middleware (method_not_allowed_middleware routes) app
;;

let param (req : req) (name : string) : string = Opium.Std.param req name

let query (req : req) (name : string) : string list =
  let uri = Opium.Std.Request.uri req in
  Uri.query uri
  |> List.filter_map ~f:(fun (candidate, values) ->
    if String.equal candidate name then
      Some (String.concat values ~sep:",")
    else
      None)
;;

let header (req : req) name = Cohttp.Header.get (Opium.Std.Request.headers req) name

let body_to_string ~max_bytes (req : req) =
  let stream = Opium.Std.Request.body req |> Opium.Std.Body.to_stream in
  let buffer = Buffer.create (Int.min max_bytes 4096) in
  let rec read size =
    let open Io.Let_syntax in
    let%bind chunk = Lwt_stream.get stream in
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

let respond ?status ~headers ~body () : resp Lwt.t =
  Opium.Std.respond' ~headers:(Cohttp.Header.of_list headers) ?code:status (`String body)
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
