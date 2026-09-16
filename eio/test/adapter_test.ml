open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_eio)
open Endpoint

module Conformance = Typed_endpoint_testing.Backend_conformance.Make (struct
    module Backend = Typed_endpoint_eio

    let call app ?(headers = []) ?(body = "") meth target =
      let request =
        Http.Request.make ~meth ~headers:(Http.Header.of_list headers) target
      in
      Typed_endpoint_eio.dispatch app ~request ~body
    ;;

    let status response =
      Typed_endpoint_eio.Response.status response |> Cohttp.Code.code_of_status
    ;;

    let header response name =
      Http.Header.get (Typed_endpoint_eio.Response.headers response) name
    ;;

    let body = Typed_endpoint_eio.Response.body
  end)

module String_param = struct
  type t = string

  let of_string value = Ok value

  let metadata : t Metadata.t =
    Metadata.v ~schema:(Json_schema.string_exn ()) ~description:"String parameter" ()
  ;;
end

module Error_payload = struct
  type t = { message : string }

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (Json_schema.Unsafe.of_yojson
           (`Assoc
               [ "type", `String "object"
               ; "properties", `Assoc [ "message", `Assoc [ "type", `String "string" ] ]
               ]))
      ~description:"Error"
      ()
  ;;

  let to_yojson error = `Assoc [ "message", `String error.message ]
end

let decode_errors =
  Decode_error_response.json
    ~payload:(module Error_payload)
    ~map:(fun _error -> Error_payload.{ message = "decode error" })
;;

let authenticated =
  Guard.v
    ~status:`Unauthorized
    ~response:(Response.text ~description:"Unauthorized" ())
    ~check:(fun request ->
      match Typed_endpoint_eio.Request.header request "authorization" with
      | Some "Bearer secret" -> Ok "alice"
      | _ -> Error "unauthorized")
    ()
;;

let route =
  post / "items" /: arg "id" (module String_param) /? arg "q" (module String_param)
  |> documented
  |> accepts (Request.text ~description:"Body" ())
  |> returns (case `OK (Response.text ~description:"OK" ()))
  |> handle_with ~context:(Context.both authenticated (Dependency.value "items"))
     @@ fun id query ok (user, service) body ->
     respond
       ok
       (String.concat
          ~sep:":"
          [ service; user; id; Option.value query ~default:"none"; body ])
;;

let captured =
  Unsafe.route ~meth:`GET ~path:"/priority/:value" ~handler:(fun request ->
    Typed_endpoint_eio.respond_string
      ("capture:" ^ Typed_endpoint_eio.param request "value"))
;;

let fixed =
  Unsafe.route ~meth:`GET ~path:"/priority/fixed" ~handler:(fun _request ->
    Typed_endpoint_eio.respond_string "static")
;;

let app =
  compile_exn
    ~decode_error:decode_errors
    [ Group.make ~prefix:[ "v1" ] ~description:"Eio test" [ route; captured; fixed ] ]
  |> Compiled.app
;;

let dispatch ?authorization ?(meth = `POST) target body =
  let headers = Http.Header.init_with "content-type" "text/plain" in
  let headers =
    Option.value_map authorization ~default:headers ~f:(fun value ->
      Http.Header.add headers "authorization" value)
  in
  let request = Http.Request.make ~meth ~headers target in
  Typed_endpoint_eio.dispatch app ~request ~body
;;

let () =
  let rejected = dispatch "/v1/items/42?q=hello" "body" in
  assert (
    Http.Status.compare (Typed_endpoint_eio.Response.status rejected) `Unauthorized = 0);
  assert (String.equal (Typed_endpoint_eio.Response.body rejected) "unauthorized");
  let accepted = dispatch ~authorization:"Bearer secret" "/v1/items/42?q=hello" "body" in
  assert (Http.Status.compare (Typed_endpoint_eio.Response.status accepted) `OK = 0);
  assert (
    Option.equal
      String.equal
      (Http.Header.get (Typed_endpoint_eio.Response.headers accepted) "content-type")
      (Some "text/plain; charset=utf-8"));
  assert (
    String.equal (Typed_endpoint_eio.Response.body accepted) "items:alice:42:hello:body");
  let wrong_method = dispatch ~meth:`GET "/v1/items/42?q=hello" "" in
  assert (
    Http.Status.compare
      (Typed_endpoint_eio.Response.status wrong_method)
      `Method_not_allowed
    = 0);
  assert (
    Option.equal
      String.equal
      (Http.Header.get (Typed_endpoint_eio.Response.headers wrong_method) "allow")
      (Some "POST"));
  let fixed = dispatch ~meth:`GET "/v1/priority/fixed" "" in
  assert (String.equal (Typed_endpoint_eio.Response.body fixed) "static");
  let calls = ref [] in
  let middleware name ~request ~next =
    calls := !calls @ [ name ^ ":before" ];
    let response = next request in
    calls := !calls @ [ name ^ ":after" ];
    response
  in
  let logged =
    let request = Http.Request.make ~meth:`GET "/v1/priority/fixed" in
    Typed_endpoint_eio.dispatch
      ~middlewares:[ middleware "outer"; middleware "inner" ]
      app
      ~request
      ~body:""
  in
  assert (String.equal (Typed_endpoint_eio.Response.body logged) "static");
  assert (
    List.equal
      String.equal
      !calls
      [ "outer:before"; "inner:before"; "inner:after"; "outer:after" ]);
  let add_request_id ~request ~next =
    let headers =
      Http.Header.replace (Http.Request.headers request) "x-request-id" "generated"
    in
    next ({ request with headers } : Http.Request.t)
  in
  let observe_request_id ~request ~next =
    assert (
      Option.equal
        String.equal
        (Http.Header.get (Http.Request.headers request) "x-request-id")
        (Some "generated"));
    next request
  in
  let request = Http.Request.make ~meth:`GET "/v1/priority/fixed" in
  let _response =
    Typed_endpoint_eio.dispatch
      ~middlewares:[ add_request_id; observe_request_id ]
      app
      ~request
      ~body:""
  in
  let with_header =
    Typed_endpoint_eio.Response.with_header logged ~name:"x-test" ~value:"value"
  in
  let with_header =
    Typed_endpoint_eio.Response.with_header
      with_header
      ~name:"x-test"
      ~value:"replacement"
  in
  assert (
    Option.equal
      String.equal
      (Http.Header.get (Typed_endpoint_eio.Response.headers with_header) "x-test")
      (Some "replacement"));
  Conformance.run ()
;;
