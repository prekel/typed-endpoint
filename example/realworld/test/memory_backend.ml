open! Base
include Cohttp.Code

type req =
  { meth : meth
  ; uri : Uri.t
  ; body : string
  ; headers : Cohttp.Header.t
  ; params : (string * string) list
  }

type resp =
  { status : status_code
  ; headers : Cohttp.Header.t
  ; body : string
  }

type 'a io = 'a

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
let return value = value
let bind value ~f = f value
let empty = []
let combine = List.append

let path_segments path =
  String.split path ~on:'/'
  |> List.filter ~f:(Fn.non String.is_empty)
  |> List.map ~f:Uri.pct_decode
;;

let route meth path handler =
  let path =
    path_segments path
    |> List.map ~f:(fun segment ->
      match String.chop_prefix segment ~prefix:":" with
      | Some name -> Param name
      | None -> Static segment)
  in
  [ { meth; path; handler } ]
;;

let rec match_path pattern actual params =
  match pattern, actual with
  | [], [] -> Some (List.rev params)
  | Static expected :: pattern, value :: actual when String.equal expected value ->
    match_path pattern actual params
  | Param name :: pattern, value :: actual ->
    match_path pattern actual ((name, value) :: params)
  | _ -> None
;;

let param (request : req) name =
  List.Assoc.find_exn request.params name ~equal:String.equal
;;

let query (request : req) name = Uri.get_query_param request.uri name
let body_to_string (request : req) = request.body

let respond_string ?(status = `OK) body =
  { status; headers = Cohttp.Header.init (); body }
;;

let respond_json ?(status = `OK) json =
  { status
  ; headers = Cohttp.Header.init_with "content-type" "application/json"
  ; body = Yojson.Safe.to_string json
  }
;;

let dispatch routes ?(headers = Cohttp.Header.init ()) ~meth ~target ~body () =
  let uri = Uri.of_string target in
  let actual = Uri.path uri |> path_segments in
  let matching_paths =
    List.filter_map routes ~f:(fun route ->
      Option.map (match_path route.path actual []) ~f:(fun params -> route, params))
  in
  match
    List.find matching_paths ~f:(fun (route, _params) ->
      compare_method route.meth meth = 0)
  with
  | Some (route, params) -> route.handler { meth; uri; body; headers; params }
  | None when not (List.is_empty matching_paths) ->
    respond_string ~status:`Method_not_allowed "Method not allowed"
  | None -> respond_string ~status:`Not_found "Not found"
;;

module Request = struct
  type t = req

  let header (request : t) name = Cohttp.Header.get request.headers name
end

module Response = struct
  type t = resp

  let status (response : t) = code_of_status response.status
  let body (response : t) = response.body
end
