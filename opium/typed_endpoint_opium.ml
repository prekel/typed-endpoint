open! Base

type req = Opium.Std.Request.t
type resp = Opium.Std.Response.t
type 'a io = 'a Lwt.t

include Cohttp.Code

type app_builder = Opium.Std.App.t -> Opium.Std.App.t

let get : meth = `GET
let post : meth = `POST
let put : meth = `PUT
let delete : meth = `DELETE
let patch : meth = `PATCH
let return = Lwt.return
let bind value ~f = Lwt.bind value f
let empty : app_builder = Fn.id
let combine (a : app_builder) (b : app_builder) : app_builder = fun app -> app |> a |> b

let route (m : meth) (path : string) (h : req -> resp Lwt.t) : app_builder =
  match m with
  | `GET -> Opium.Std.get path h
  | `POST -> Opium.Std.post path h
  | `PUT -> Opium.Std.put path h
  | `DELETE -> Opium.Std.delete path h
  | `PATCH -> Opium.Std.App.patch path h
  | meth -> Opium.Std.App.action meth path h
;;

let param (req : req) (name : string) : string = Opium.Std.param req name

let query (req : req) (name : string) : string option =
  let uri = Opium.Std.Request.uri req in
  Uri.get_query_param uri name
;;

let body_to_string (req : req) : string Lwt.t =
  Opium.Std.Request.body req |> Opium.Std.Body.to_string
;;

let respond_string ?status (s : string) : resp Lwt.t =
  Opium.App.respond' ?code:status (`String s)
;;

let respond_json ?status (json : Yojson.Safe.t) : resp Lwt.t =
  let headers = Cohttp.Header.init_with "content-type" "application/json" in
  let s = Yojson.Safe.to_string json in
  Opium.Std.respond' ~headers ?code:status (`String s)
;;
