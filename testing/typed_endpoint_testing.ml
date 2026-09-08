open! Base

type request =
  { meth : Cohttp.Code.meth
  ; target : string
  ; uri : Uri.t
  ; headers : (string * string) list
  ; body : string
  ; params : (string * string) list
  }

type response =
  { status : int
  ; headers : (string * string) list
  ; body : string
  }

type req = request
type resp = response
type 'a io = 'a
type body_read_error = [ `Too_large ]

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
  ; handler : request -> response
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

let route_segment segment =
  match String.chop_prefix segment ~prefix:":" with
  | Some name -> Param name
  | None -> Static segment
;;

let route meth path handler =
  [ { meth; path = List.map (path_segments path) ~f:route_segment; handler } ]
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

let param request name = List.Assoc.find_exn request.params name ~equal:String.equal
let query request name = Uri.get_query_param request.uri name

let header (request : request) name =
  List.find_map request.headers ~f:(fun (candidate, value) ->
    if String.Caseless.equal candidate name then
      Some value
    else
      None)
;;

let body_to_string ~max_bytes (request : request) =
  if String.length request.body > max_bytes then
    Error `Too_large
  else
    Ok request.body
;;

let respond_empty ?(status = `OK) () =
  { status = code_of_status status; headers = []; body = "" }
;;

let respond_string ?(status = `OK) body =
  { status = code_of_status status
  ; headers = [ "content-type", "text/plain; charset=utf-8" ]
  ; body
  }
;;

let respond_html ?(status = `OK) body =
  { status = code_of_status status
  ; headers = [ "content-type", "text/html; charset=utf-8" ]
  ; body
  }
;;

let respond_json ?(status = `OK) json =
  { status = code_of_status status
  ; headers = [ "content-type", "application/json" ]
  ; body = Yojson.Safe.to_string json
  }
;;

module Request = struct
  let v ?(headers = []) ?(body = "") ~meth ~target () =
    { meth; target; uri = Uri.of_string target; headers; body; params = [] }
  ;;

  let meth (request : request) = request.meth
  let target (request : request) = request.target
end

module Response = struct
  let status response = response.status
  let headers response = response.headers
  let body response = response.body

  let header response name =
    List.find_map response.headers ~f:(fun (candidate, value) ->
      if String.Caseless.equal candidate name then
        Some value
      else
        None)
  ;;

  let json response =
    try Ok (Yojson.Safe.from_string response.body) with
    | Yojson.Json_error error -> Error error
  ;;
end

let dispatch routes request =
  let path = request.uri |> Uri.path |> path_segments in
  let matches =
    List.filter_map routes ~f:(fun route ->
      Option.map (match_path route.path path []) ~f:(fun params -> route, params))
  in
  match
    List.find matches ~f:(fun (route, _) ->
      Int.equal (compare_method route.meth request.meth) 0)
  with
  | Some (route, params) -> route.handler { request with params }
  | None when not (List.is_empty matches) ->
    let allow =
      matches
      |> List.map ~f:(fun (route, _params) -> string_of_method route.meth)
      |> List.dedup_and_sort ~compare:String.compare
      |> String.concat ~sep:", "
    in
    let response = respond_string ~status:`Method_not_allowed "Method not allowed" in
    { response with headers = ("allow", allow) :: response.headers }
  | None -> respond_string ~status:`Not_found "Not found"
;;

module Client = struct
  let call routes ?headers ?body meth target =
    Request.v ?headers ?body ~meth ~target () |> dispatch routes
  ;;
end
