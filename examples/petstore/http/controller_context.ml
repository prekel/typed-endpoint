open! Base
module Petstore_principal = Principal
open Typed_endpoint

module Make (B : Backend.S) (Sessions : Session_service.S with type 'a io = 'a B.io) =
struct
  module Endpoint = Typed_endpoint.Make (B)
  open Endpoint

  module Secured = struct
    type 'a t =
      { dependency : 'a
      ; principal : Petstore_principal.t
      ; request_id : string option
      }

    let dependency context = context.dependency
    let principal context = context.principal
    let request_id context = context.request_id
  end

  let bearer =
    Security.Scheme.http_bearer
      ~name:"session_auth"
      ~description:"Login session or administrative development demo bearer"
      ()
  ;;

  let api_key_scheme =
    Security.Scheme.api_key
      ~name:"api_key"
      ~parameter:"api_key"
      ~location:`Header
      ~description:"Petstore API key"
      ()
  ;;

  type access =
    { bearer : bool
    ; api_key : bool
    ; security : Security.requirement list
    }

  let bearer_access =
    { bearer = true; api_key = false; security = [ Security.require bearer ] }
  ;;

  let api_key_access =
    { bearer = false; api_key = true; security = [ Security.require api_key_scheme ] }
  ;;

  let management_access =
    { bearer = true
    ; api_key = true
    ; security = [ Security.require bearer; Security.require api_key_scheme ]
    }
  ;;

  let authorize ~auth ~database access =
    Guard.authenticate
      ~security:access.security
      ~status:`Unauthorized
      ~response:
        (Response.json ~description:"Authentication required" (module Dto.Api_response))
      ~check:(fun request ->
        let token =
          B.header request "authorization" |> Option.bind ~f:Auth.bearer_token
        in
        let key_valid =
          access.api_key
          && (not (String.is_empty auth.Auth.api_key))
          && Option.value_map (B.header request "api_key") ~default:false ~f:(fun key ->
            (not (String.is_empty key)) && String.equal key auth.api_key)
        in
        let rejected () =
          Error
            Dto.Api_response.
              { code = 401; type_ = "unauthorized"; message = "invalid credentials" }
        in
        let open B.Io.Let_syntax in
        if key_valid then
          B.Io.return (Ok (Petstore_principal.api_key ()))
        else (
          match
            token
          with
          | Some token
            when access.bearer
                 && (not (String.is_empty auth.bearer_token))
                 && String.equal token auth.bearer_token ->
            B.Io.return (Ok (Petstore_principal.demo ()))
          | Some token when access.bearer ->
            let%map result = Sessions.find ~database token in
            (match result with
             | Ok (Some session) ->
               Ok
                 (Petstore_principal.session
                    ~username:session.username
                    ~token:session.token)
             | Ok None | Error _ -> rejected ())
          | _ -> B.Io.return (rejected ())))
      ()
  ;;

  let secured ~auth ~access dependency =
    let request_id =
      Dependency.of_request (fun request -> B.Io.return (B.header request "x-request-id"))
    in
    let open Context.Let_syntax in
    let%map authenticated = authorize ~auth ~database:dependency access
    and correlation_id = request_id
    and application = Dependency.value dependency in
    Secured.
      { dependency = application; principal = authenticated; request_id = correlation_id }
  ;;

  let session ~auth dependency = secured ~auth ~access:bearer_access dependency
  let pet_lookup ~auth dependency = secured ~auth ~access:management_access dependency
  let management ~auth dependency = secured ~auth ~access:management_access dependency
  let api_key ~auth dependency = secured ~auth ~access:api_key_access dependency
  let public dependency = Dependency.value dependency

  let decode_errors =
    Decode_error_response.json
      ~payload:(module Dto.Api_response)
      ~map:Dto.Api_response.of_decode_error
    |> Decode_error_response.with_description (function
      | `Bad_request -> Some "Invalid request"
      | `Request_entity_too_large -> Some "Request body too large"
      | `Unsupported_media_type -> Some "Unsupported media type"
      | _ -> None)
  ;;
end
