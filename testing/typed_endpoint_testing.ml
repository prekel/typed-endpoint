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

let query request name =
  Uri.query request.uri
  |> List.filter_map ~f:(fun (candidate, values) ->
    if String.equal candidate name then
      Some (String.concat values ~sep:",")
    else
      None)
;;

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

let respond ?(status = `OK) ~headers ~body () =
  { status = code_of_status status; headers; body }
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
    let response =
      respond
        ~status:`Method_not_allowed
        ~headers:[ "content-type", "text/plain; charset=utf-8" ]
        ~body:"Method not allowed"
        ()
    in
    { response with headers = ("allow", allow) :: response.headers }
  | None ->
    respond
      ~status:`Not_found
      ~headers:[ "content-type", "text/plain; charset=utf-8" ]
      ~body:"Not found"
      ()
;;

module Client = struct
  let call routes ?headers ?body meth target =
    Request.v ?headers ?body ~meth ~target () |> dispatch routes
  ;;
end

module Backend_conformance = struct
  module type Harness = sig
    module Backend : Typed_endpoint.Backend.S

    val call
      :  Backend.app_builder
      -> ?headers:(string * string) list
      -> ?body:string
      -> Backend.meth
      -> string
      -> Backend.resp Backend.io

    val status : Backend.resp -> int
    val header : Backend.resp -> string -> string option
    val body : Backend.resp -> string Backend.io
  end

  module Make (H : Harness) = struct
    module B = H.Backend
    module Endpoint = Typed_endpoint.Make (B)
    open Endpoint
    open Dsl
    open Staged

    let check condition message =
      if not condition then
        failwith ("backend conformance: " ^ message)
    ;;

    let text description = Response.text ~description ()

    let endpoint uri request responses handler =
      let ready = uri |> documented () |> accepts request |> returns responses in
      handle ready handler
    ;;

    let endpoint_with ~context uri request responses handler =
      let ready = uri |> documented () |> accepts request |> returns responses in
      handle_with ~context ready handler
    ;;

    let bounded =
      endpoint
        (post / "bounded")
        (Request.text ~max_body_bytes:4 ~description:"Bounded body" ())
        (ok (text "Echo"))
        (fun body -> B.Io.return (OK body))
    ;;

    let header_route =
      endpoint_with
        ~context:Context.request
        (get / "header")
        Request.empty
        (ok (text "Header"))
        (fun request () ->
           B.Io.return
             (OK (Option.value (B.header request "x-conformance") ~default:"none")))
    ;;

    let typed_request_header =
      Typed_endpoint.Header.required
        "X-Conformance-Version"
        (Typed_endpoint.Header.int ~description:"Protocol version" ())
    ;;

    let typed_response_header =
      Typed_endpoint.Header.required
        "X-Conformance-Result"
        (Typed_endpoint.Header.string ~description:"Conformance marker" ())
    ;;

    let typed_headers =
      endpoint
        (get / "typed-headers" |> header typed_request_header)
        Request.empty
        (ok
           (Response.text ~description:"Typed headers" ()
            |> Response.with_header typed_response_header))
        (fun version () ->
           B.Io.return (OK ("present", "version:" ^ Int.to_string version)))
    ;;

    let empty_route =
      endpoint
        (get / "empty")
        Request.empty
        (ok (Response.empty ~description:"Empty" ()))
        (fun () -> B.Io.return (OK ()))
    ;;

    let decoded =
      endpoint
        (get
         / "decoded"
         /: arg "id" (Typed_endpoint.Parameter.int ~description:"Identifier" ())
         /! arg "enabled" (Typed_endpoint.Parameter.bool ~description:"Enabled" ()))
        Request.empty
        (ok (text "Decoded"))
        (fun id enabled () ->
           B.Io.return (OK (Int.to_string id ^ ":" ^ Bool.to_string enabled)))
    ;;

    let captured =
      endpoint
        (get
         / "priority"
         /: arg "value" (Typed_endpoint.Parameter.string ~description:"Value" ()))
        Request.empty
        (ok (text "Captured"))
        (fun value () -> B.Io.return (OK ("capture:" ^ value)))
    ;;

    let fixed =
      endpoint
        (get / "priority" / "fixed")
        Request.empty
        (ok (text "Static"))
        (fun () -> B.Io.return (OK "static"))
    ;;

    let method_get =
      endpoint
        (get / "methods")
        Request.empty
        (ok (text "GET"))
        (fun () -> B.Io.return (OK "get"))
    ;;

    let method_post =
      endpoint
        (post / "methods")
        Request.empty
        (ok (text "POST"))
        (fun () -> B.Io.return (OK "post"))
    ;;

    let app =
      compile_exn
        [ Group.make
            ~description:"Backend conformance"
            [ bounded
            ; header_route
            ; typed_headers
            ; empty_route
            ; decoded
            ; captured
            ; fixed
            ; method_get
            ; method_post
            ]
        ]
      |> Compiled.app
    ;;

    let body response = H.body response

    let check_response response ~status ~content_type =
      check
        (Int.equal (H.status response) status)
        ("expected status "
         ^ Int.to_string status
         ^ ", got "
         ^ Int.to_string (H.status response));
      check
        (Option.equal String.equal (H.header response "content-type") content_type)
        "unexpected Content-Type"
    ;;

    let run () =
      let open B.Io.Let_syntax in
      let%bind echoed =
        H.call
          app
          ~headers:[ "content-type", "text/plain" ]
          ~body:"data"
          B.post
          "/bounded"
      in
      check_response echoed ~status:200 ~content_type:(Some "text/plain; charset=utf-8");
      let%bind echoed_body = body echoed in
      check (String.equal echoed_body "data") "text response body";
      let%bind too_large =
        H.call
          app
          ~headers:[ "content-type", "text/plain" ]
          ~body:"large"
          B.post
          "/bounded"
      in
      check_response too_large ~status:413 ~content_type:(Some "application/json");
      let%bind too_large_body = body too_large in
      check
        (String.is_substring too_large_body ~substring:"body_too_large")
        "body limit error shape";
      let%bind unsupported =
        H.call
          app
          ~headers:[ "content-type", "application/json" ]
          ~body:"data"
          B.post
          "/bounded"
      in
      check_response unsupported ~status:415 ~content_type:(Some "application/json");
      let%bind reflected =
        H.call app ~headers:[ "X-Conformance", "present" ] B.get "/header"
      in
      let%bind reflected_body = body reflected in
      check (String.equal reflected_body "present") "case-insensitive request header";
      let%bind typed_headers =
        H.call app ~headers:[ "x-conformance-version", "7" ] B.get "/typed-headers"
      in
      check_response
        typed_headers
        ~status:200
        ~content_type:(Some "text/plain; charset=utf-8");
      check
        (Option.equal
           String.equal
           (H.header typed_headers "X-Conformance-Result")
           (Some "present"))
        "typed response header";
      let%bind typed_headers_body = body typed_headers in
      check (String.equal typed_headers_body "version:7") "typed request header";
      let%bind missing_header = H.call app B.get "/typed-headers" in
      check (Int.equal (H.status missing_header) 400) "missing typed header status";
      let%bind invalid_header =
        H.call app ~headers:[ "X-Conformance-Version", "invalid" ] B.get "/typed-headers"
      in
      check (Int.equal (H.status invalid_header) 400) "invalid typed header status";
      let%bind empty = H.call app B.get "/empty" in
      check_response empty ~status:200 ~content_type:None;
      let%bind empty_body = body empty in
      check (String.is_empty empty_body) "empty response body";
      let%bind missing = H.call app B.get "/missing" in
      check (Int.equal (H.status missing) 404) "404 status";
      let%bind wrong_method = H.call app B.put "/methods" in
      check_response
        wrong_method
        ~status:405
        ~content_type:(Some "text/plain; charset=utf-8");
      check
        (Option.equal String.equal (H.header wrong_method "allow") (Some "GET, POST"))
        "405 Allow header";
      let%bind fixed_response = H.call app B.get "/priority/fixed" in
      let%bind fixed_body = body fixed_response in
      check (String.equal fixed_body "static") "static route priority";
      let%bind captured_response = H.call app B.get "/priority/other" in
      let%bind captured_body = body captured_response in
      check (String.equal captured_body "capture:other") "captured route";
      let%bind invalid = H.call app B.get "/decoded/nope?enabled=true" in
      check_response invalid ~status:400 ~content_type:(Some "application/json");
      let%bind invalid_body = body invalid in
      check
        (String.is_substring invalid_body ~substring:"invalid_parameter")
        "invalid parameter error shape";
      let%bind absent = H.call app B.get "/decoded/42" in
      check (Int.equal (H.status absent) 400) "missing query status";
      let%bind duplicate = H.call app B.get "/decoded/42?enabled=true&enabled=false" in
      check (Int.equal (H.status duplicate) 400) "duplicate scalar query status";
      let%bind duplicate_body = body duplicate in
      check
        (String.is_substring duplicate_body ~substring:"duplicate_parameter")
        "duplicate scalar query shape";
      let ordered =
        B.combine
          (B.route B.get "/ordered/:first" (fun _request ->
             B.respond
               ~headers:[ "content-type", "text/plain; charset=utf-8" ]
               ~body:"first"
               ()))
          (B.route B.get "/ordered/:second" (fun _request ->
             B.respond
               ~headers:[ "content-type", "text/plain; charset=utf-8" ]
               ~body:"second"
               ()))
      in
      let%bind ordered_response = H.call ordered B.get "/ordered/value" in
      let%map ordered_body = body ordered_response in
      check (String.equal ordered_body "first") "route declaration order"
    ;;
  end
end
