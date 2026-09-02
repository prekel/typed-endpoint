open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_eio)
open Endpoint
open Endpoint.Dsl

module String_param = struct
  type t = string

  let of_string value = Ok value

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:(`Assoc [ "type", `String "string" ])
      ~description:"String parameter"
      ()
  ;;
end

module Error_payload = struct
  type t = { message : string }

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (`Assoc
            [ "type", `String "object"
            ; "properties", `Assoc [ "message", `Assoc [ "type", `String "string" ] ]
            ])
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
  let context = Context.both authenticated (Dependency.value "items") in
  make_with
    ~context
    ~meth:B.post
    ~path:
      (s "items"
       / param "id" (module String_param)
       / query "q" (module String_param)
       /? nil)
    ~request:(Request.text ~description:"Body" ())
    ~responses:(ok (Response.text ~description:"OK" ()))
  @@ fun id query (user, service) body ->
  OK
    (String.concat
       ~sep:":"
       [ service; user; id; Option.value query ~default:"none"; body ])
;;

let app =
  compile_exn
    ~decode_error:decode_errors
    [ Group.v
        ~prefix:[ "v1" ]
        ~metadata:(Operation_metadata.v ~description:"Eio test" ())
        [ route ]
    ]
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
    String.equal (Typed_endpoint_eio.Response.body accepted) "items:alice:42:hello:body");
  let wrong_method = dispatch ~meth:`GET "/v1/items/42?q=hello" "" in
  assert (
    Http.Status.compare
      (Typed_endpoint_eio.Response.status wrong_method)
      `Method_not_allowed
    = 0)
;;
