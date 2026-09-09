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

type app_builder = Opium.Std.App.t -> Opium.Std.App.t

let get : meth = `GET
let post : meth = `POST
let put : meth = `PUT
let delete : meth = `DELETE
let patch : meth = `PATCH
let empty : app_builder = Fn.id

let combine (first : app_builder) (second : app_builder) : app_builder =
  fun app -> app |> second |> first
;;

let method_not_allowed_middleware (m : meth) path =
  let route = Opium.Std.Route.of_string path in
  Opium.Std.Rock.Middleware.create
    ~name:"typed-endpoint-method-not-allowed"
    ~filter:(fun next request ->
      let open Io.Let_syntax in
      let%map response = next request in
      let status = Cohttp.Code.code_of_status response.code in
      let path_matches =
        Opium.Std.Route.match_url route (Opium.Std.Request.uri request |> Uri.path)
        |> Option.is_some
      in
      if path_matches && (Int.equal status 404 || Int.equal status 405) then (
        let methods =
          Cohttp.Header.get response.headers "allow"
          |> Option.value_map ~default:[] ~f:(fun value ->
            String.split value ~on:',' |> List.map ~f:String.strip)
          |> List.cons (Cohttp.Code.string_of_method m)
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
  let register =
    match m with
    | `GET -> Opium.Std.get path h
    | `POST -> Opium.Std.post path h
    | `PUT -> Opium.Std.put path h
    | `DELETE -> Opium.Std.delete path h
    | `PATCH -> Opium.Std.App.patch path h
    | meth -> Opium.Std.App.action meth path h
  in
  fun app ->
    app |> register |> Opium.Std.App.middleware (method_not_allowed_middleware m path)
;;

let param (req : req) (name : string) : string = Opium.Std.param req name

let query (req : req) (name : string) : string option =
  let uri = Opium.Std.Request.uri req in
  Uri.get_query_param uri name
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

let respond_empty ?status () : resp Lwt.t = Opium.App.respond' ?code:status (`String "")

let respond_string ?status (s : string) : resp Lwt.t =
  let headers = Cohttp.Header.init_with "content-type" "text/plain; charset=utf-8" in
  Opium.App.respond' ~headers ?code:status (`String s)
;;

let respond_html ?status (html : string) : resp Lwt.t =
  let headers = Cohttp.Header.init_with "content-type" "text/html; charset=utf-8" in
  Opium.Std.respond' ~headers ?code:status (`String html)
;;

let respond_json ?status (json : Yojson.Safe.t) : resp Lwt.t =
  let headers = Cohttp.Header.init_with "content-type" "application/json" in
  let s = Yojson.Safe.to_string json in
  Opium.Std.respond' ~headers ?code:status (`String s)
;;
