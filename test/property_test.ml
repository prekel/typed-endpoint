open! Base
open Typed_endpoint
module Endpoint = Make (Typed_endpoint_testing)
open Endpoint
open Dsl
open Staged

let group routes = Group.make ~description:"Property tests" routes
let call = Typed_endpoint_testing.Client.call

let segment_route =
  let ok = Response.case `OK (Response.text ~description:"Echo" ()) in
  get / "segment" /: arg "value" (Parameter.string ~description:"Segment" ())
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun value () -> respond ok value
;;

let query_route =
  let ok = Response.case `OK (Response.text ~description:"Value" ()) in
  get / "query" /! arg "value" (Parameter.int ~description:"Scalar value" ())
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun value () -> respond ok (Int.to_string value)
;;

let version_header =
  Header.required "X-Api-Version" (Header.int ~description:"API version" ())
;;

let header_route =
  let ok = Response.case `OK (Response.text ~description:"Version" ()) in
  get / "header"
  |> header version_header
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun version () -> respond ok (Int.to_string version)
;;

let priority_dynamic_route =
  let ok = Response.case `OK (Response.text ~description:"Route kind" ()) in
  get / "priority" /: arg "value" (Parameter.string ~description:"Value" ())
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun _value () -> respond ok "dynamic"
;;

let priority_static_route =
  let ok = Response.case `OK (Response.text ~description:"Route kind" ()) in
  get / "priority" / "fixed"
  |> documented
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun () -> respond ok "static"
;;

let app =
  compile_exn [ group [ segment_route; query_route; header_route ] ] |> Compiled.app
;;

let priority_apps =
  let compile routes = compile_exn [ group routes ] |> Compiled.app in
  ( compile [ priority_static_route; priority_dynamic_route ]
  , compile [ priority_dynamic_route; priority_static_route ] )
;;

let segment =
  let open QCheck2.Gen in
  let characters =
    [ 'a'; 'z'; '0'; '9'; ' '; '%'; '?'; '#'; '+'; '-'; '_'; '~'; ':'; '@' ]
  in
  let* length = int_range 1 24 in
  let+ characters = list_size (return length) (oneof_list characters) in
  String.of_char_list characters
;;

let percent_decoding =
  QCheck2.Test.make
    ~name:"path capture receives exactly one percent-decoded segment"
    ~count:500
    ~print:Fn.id
    segment
    (fun value ->
       let target = "/segment/" ^ Uri.pct_encode ~component:`Path value in
       let response = call app `GET target in
       Int.equal (Typed_endpoint_testing.Response.status response) 200
       && String.equal (Typed_endpoint_testing.Response.body response) value)
;;

let duplicate_scalar_query =
  QCheck2.Test.make
    ~name:"duplicate scalar query values are rejected"
    ~count:500
    QCheck2.Gen.(pair int_small int_small)
    (fun (first, second) ->
       let target =
         "/query?value=" ^ Int.to_string first ^ "&value=" ^ Int.to_string second
       in
       let response = call app `GET target in
       Int.equal (Typed_endpoint_testing.Response.status response) 400)
;;

let header_case =
  QCheck2.Test.make
    ~name:"typed request header names are case-insensitive"
    ~count:500
    QCheck2.Gen.(pair int_small bool)
    (fun (version, uppercase) ->
       let name =
         if uppercase then
           "X-API-VERSION"
         else
           "x-api-version"
       in
       let response = call app ~headers:[ name, Int.to_string version ] `GET "/header" in
       Int.equal (Typed_endpoint_testing.Response.status response) 200
       && String.equal
            (Typed_endpoint_testing.Response.body response)
            (Int.to_string version))
;;

let static_route_priority =
  QCheck2.Test.make
    ~name:
      "static routes win over overlapping path captures regardless of declaration order"
    ~count:500
    QCheck2.Gen.bool
    (fun dynamic_first ->
       let app =
         if dynamic_first then
           snd priority_apps
         else
           fst priority_apps
       in
       let response = call app `GET "/priority/fixed" in
       Int.equal (Typed_endpoint_testing.Response.status response) 200
       && String.equal (Typed_endpoint_testing.Response.body response) "static")
;;

let () =
  QCheck_base_runner.run_tests_main
    [ percent_decoding; duplicate_scalar_query; header_case; static_route_priority ]
;;
