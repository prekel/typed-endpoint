open! Base

type request =
  { meth : Typed_endpoint.Method.t
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

module Io = struct
  type 'a t = 'a io

  include Base.Monad.Make (struct
      type nonrec 'a t = 'a io

      let return value = value
      let bind value ~f = f value
      let map = `Custom (fun value ~f -> f value)
    end)
end

type segment =
  | Static of string
  | Param of string

type route =
  { meth : Typed_endpoint.Method.t
  ; path : segment list
  ; handler : request -> response
  }

type app_builder = route list

let empty = []
let combine = List.append

let method_to_string : Typed_endpoint.Method.t -> string = function
  | `GET -> "GET"
  | `POST -> "POST"
  | `HEAD -> "HEAD"
  | `DELETE -> "DELETE"
  | `PATCH -> "PATCH"
  | `PUT -> "PUT"
  | `OPTIONS -> "OPTIONS"
  | `TRACE -> "TRACE"
  | `CONNECT -> "CONNECT"
  | `Other method_ -> method_
;;

let path_segments path =
  String.split path ~on:'/'
  |> List.filter ~f:(Fn.non String.is_empty)
  |> List.map ~f:Uri.pct_decode
;;

let route_segment segment =
  match String.chop_prefix segment ~prefix:":" with
  | Some name -> Param name
  | None -> Static (Uri.pct_decode segment)
;;

let route meth path handler =
  [ { meth
    ; path =
        List.map
          (String.split path ~on:'/' |> List.filter ~f:(Fn.non String.is_empty))
          ~f:route_segment
    ; handler
    }
  ]
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
  { status = Typed_endpoint.Status.code status; headers; body }
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
  match List.find matches ~f:(fun (route, _) -> Poly.equal route.meth request.meth) with
  | Some (route, params) -> route.handler { request with params }
  | None when not (List.is_empty matches) ->
    let allow =
      matches
      |> List.map ~f:(fun (route, _params) -> method_to_string route.meth)
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
      -> Typed_endpoint.Method.t
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
    open Io.Let_syntax

    let check condition message =
      if not condition then
        failwith ("backend conformance: " ^ message)
    ;;

    let text description = Response.text ~description ()

    let endpoint uri request response handler =
      uri |> documented |> accepts request |> returns (case `OK response) ==> handler
    ;;

    let bounded =
      endpoint
        (post / "bounded")
        (Request.text ~max_body_bytes:4 ~description:"Bounded body" ())
        (text "Echo")
        (fun ok () body ->
           let%bind result = Request_body.read body in
           match result with
           | Ok body -> respond ok body
           | Error error -> Request_body.reject error)
    ;;

    let header_route =
      endpoint (get / "header") Request.empty (text "Header") (fun ok request () ->
        respond ok (Option.value (B.header request "x-conformance") ~default:"none"))
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
        (Response.text ~description:"Typed headers" ()
         |> Response.with_header typed_response_header)
        (fun version ok () () ->
           respond ok ("present", "version:" ^ Int.to_string version))
    ;;

    let empty_route =
      endpoint
        (get / "empty")
        Request.empty
        (Response.empty ~description:"Empty" ())
        (fun ok () () -> respond ok ())
    ;;

    let decoded =
      endpoint
        (get
         / "decoded"
         /: arg "id" (Typed_endpoint.Parameter.int ~description:"Identifier" ())
         /! arg "enabled" (Typed_endpoint.Parameter.bool ~description:"Enabled" ()))
        Request.empty
        (text "Decoded")
        (fun id enabled ok () () ->
           respond ok (Int.to_string id ^ ":" ^ Bool.to_string enabled))
    ;;

    let captured =
      endpoint
        (get
         / "priority"
         /: arg "value" (Typed_endpoint.Parameter.string ~description:"Value" ()))
        Request.empty
        (text "Captured")
        (fun value ok () () -> respond ok ("capture:" ^ value))
    ;;

    let fixed =
      endpoint
        (get / "priority" / "fixed")
        Request.empty
        (text "Static")
        (fun ok () () -> respond ok "static")
    ;;

    let method_get =
      endpoint (get / "methods") Request.empty (text "GET") (fun ok () () ->
        respond ok "get")
    ;;

    let method_post =
      endpoint (post / "methods") Request.empty (text "POST") (fun ok () () ->
        respond ok "post")
    ;;

    module Json_payload = struct
      type t = Yojson.Safe.t

      let of_yojson value = Ok value
      let to_yojson value = value

      let t_jsonschema =
        Typed_endpoint.Json_schema.with_openapi
          ~description:"JSON"
          Typed_endpoint.Json_schema.any
      ;;
    end

    let vendor_json =
      endpoint
        (post / "vendor-json")
        (Request.json
           ~media_types:[ "application/json"; "application/vnd.conformance+json" ]
           (module Json_payload))
        (Response.json (module Json_payload))
        (fun ok () body ->
           let%bind result = Request_body.read body in
           match result with
           | Ok value -> respond ok value
           | Error error -> Request_body.reject error)
    ;;

    let literal_braces =
      endpoint
        (get / "literal" / "{id}")
        Request.empty
        (text "Literal braces")
        (fun ok () () -> respond ok "literal")
    ;;

    let encoded_segments = [ "encoded-braces", "%7Bid%7D"; "encoded-percent", "%252F" ]

    let encoded_routes =
      List.map encoded_segments ~f:(fun (name, segment) ->
        endpoint
          (get
           / name
           / segment
           /: arg
                "value"
                (Typed_endpoint.Parameter.string ~description:"Captured value" ()))
          Request.empty
          (text "Encoded static segment")
          (fun value ok () () -> respond ok value))
    ;;

    let rendering_value =
      `Assoc
        [ "message", `String "Line one\nLine two\""
        ; ( "items"
          , `List
              (List.init 8 ~f:(fun index ->
                 `Assoc [ "index", `Int index; "enabled", `Bool true ])) )
        ]
    ;;

    let app =
      compile_exn
        [ Group.make_with_context
            ~context:(Context.return ())
            ~description:"Backend conformance"
            ([ vendor_json
             ; literal_braces
             ; bounded
             ; typed_headers
             ; empty_route
             ; decoded
             ; captured
             ; fixed
             ; method_get
             ; method_post
             ]
             @ encoded_routes)
        ; Group.make_with_context
            ~context:Context.request
            ~description:"Request access"
            [ header_route ]
        ; Group.make
            ~description:"JSON rendering"
            [ Unsafe.route ~meth:`GET ~path:"/pretty-json" ~handler:(fun _ ->
                B.respond_json ~status:`Accepted ~pretty:true rendering_value)
            ; Unsafe.route ~meth:`GET ~path:"/compact-json" ~handler:(fun _ ->
                B.respond_json rendering_value)
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
      let%bind pretty = H.call app `GET "/pretty-json" in
      check_response pretty ~status:202 ~content_type:(Some "application/json");
      let%bind pretty_body = body pretty in
      check (String.is_substring pretty_body ~substring:"\n  ") "pretty JSON indentation";
      check
        (Yojson.Safe.equal (Yojson.Safe.from_string pretty_body) rendering_value)
        "pretty JSON value";
      let%bind compact = H.call app `GET "/compact-json" in
      check_response compact ~status:200 ~content_type:(Some "application/json");
      let%bind compact_body = body compact in
      check
        (String.equal compact_body (Yojson.Safe.to_string rendering_value))
        "default JSON bytes";
      let%bind () =
        List.fold
          encoded_segments
          ~init:(B.Io.return ())
          ~f:(fun checks (name, segment) ->
            let%bind () = checks in
            let%bind response =
              H.call app `GET ("/" ^ name ^ "/" ^ segment ^ "/value%252F")
            in
            check (Int.equal (H.status response) 200) ("encoded static segment: " ^ name);
            let%bind actual = body response in
            check
              (String.equal actual "value%2F")
              ("capture decoded exactly once: " ^ name);
            let%map missing = H.call app `GET ("/" ^ name ^ "/different/value%252F") in
            check
              (Int.equal (H.status missing) 404)
              ("static segment became a capture: " ^ name))
      in
      let%bind literal = H.call app `GET "/literal/%7Bid%7D" in
      check (Int.equal (H.status literal) 200) "escaped literal braces status";
      let%bind literal_body = body literal in
      check (String.equal literal_body "literal") "escaped literal braces body";
      let%bind vendor =
        H.call
          app
          ~headers:[ "content-type", "application/vnd.conformance+json; charset=utf-8" ]
          ~body:{|{"value":1}|}
          `POST
          "/vendor-json"
      in
      check (Int.equal (H.status vendor) 200) "declared vendor JSON type";
      let%bind vendor_body = body vendor in
      check (String.equal vendor_body {|{"value":1}|}) "vendor JSON payload";
      let%bind undeclared =
        H.call
          app
          ~headers:[ "content-type", "application/other+json" ]
          ~body:"{}"
          `POST
          "/vendor-json"
      in
      check (Int.equal (H.status undeclared) 415) "undeclared vendor JSON type";
      let open B.Io.Let_syntax in
      let%bind echoed =
        H.call app ~headers:[ "content-type", "text/plain" ] ~body:"data" `POST "/bounded"
      in
      check_response echoed ~status:200 ~content_type:(Some "text/plain; charset=utf-8");
      let%bind echoed_body = body echoed in
      check (String.equal echoed_body "data") "text response body";
      let%bind too_large =
        H.call
          app
          ~headers:[ "content-type", "text/plain" ]
          ~body:"large"
          `POST
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
          `POST
          "/bounded"
      in
      check_response unsupported ~status:415 ~content_type:(Some "application/json");
      let%bind reflected =
        H.call app ~headers:[ "X-Conformance", "present" ] `GET "/header"
      in
      let%bind reflected_body = body reflected in
      check (String.equal reflected_body "present") "case-insensitive request header";
      let%bind typed_headers =
        H.call app ~headers:[ "x-conformance-version", "7" ] `GET "/typed-headers"
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
      let%bind missing_header = H.call app `GET "/typed-headers" in
      check (Int.equal (H.status missing_header) 400) "missing typed header status";
      let%bind invalid_header =
        H.call app ~headers:[ "X-Conformance-Version", "invalid" ] `GET "/typed-headers"
      in
      check (Int.equal (H.status invalid_header) 400) "invalid typed header status";
      let%bind empty = H.call app `GET "/empty" in
      check_response empty ~status:200 ~content_type:None;
      let%bind empty_body = body empty in
      check (String.is_empty empty_body) "empty response body";
      let%bind missing = H.call app `GET "/missing" in
      check (Int.equal (H.status missing) 404) "404 status";
      let%bind wrong_method = H.call app `PUT "/methods" in
      check_response
        wrong_method
        ~status:405
        ~content_type:(Some "text/plain; charset=utf-8");
      check
        (Option.equal String.equal (H.header wrong_method "allow") (Some "GET, POST"))
        "405 Allow header";
      let%bind fixed_response = H.call app `GET "/priority/fixed" in
      let%bind fixed_body = body fixed_response in
      check (String.equal fixed_body "static") "static route priority";
      let%bind captured_response = H.call app `GET "/priority/other" in
      let%bind captured_body = body captured_response in
      check (String.equal captured_body "capture:other") "captured route";
      let%bind invalid = H.call app `GET "/decoded/nope?enabled=true" in
      check_response invalid ~status:400 ~content_type:(Some "application/json");
      let%bind invalid_body = body invalid in
      check
        (String.is_substring invalid_body ~substring:"invalid_parameter")
        "invalid parameter error shape";
      let%bind absent = H.call app `GET "/decoded/42" in
      check (Int.equal (H.status absent) 400) "missing query status";
      let%bind duplicate = H.call app `GET "/decoded/42?enabled=true&enabled=false" in
      check (Int.equal (H.status duplicate) 400) "duplicate scalar query status";
      let%bind duplicate_body = body duplicate in
      check
        (String.is_substring duplicate_body ~substring:"duplicate_parameter")
        "duplicate scalar query shape";
      let ordered =
        B.combine
          (B.route `GET "/ordered/:first" (fun _request ->
             B.respond
               ~headers:[ "content-type", "text/plain; charset=utf-8" ]
               ~body:"first"
               ()))
          (B.route `GET "/ordered/:second" (fun _request ->
             B.respond
               ~headers:[ "content-type", "text/plain; charset=utf-8" ]
               ~body:"second"
               ()))
      in
      let%bind ordered_response = H.call ordered `GET "/ordered/value" in
      let%map ordered_body = body ordered_response in
      check (String.equal ordered_body "first") "route declaration order"
    ;;
  end
end
