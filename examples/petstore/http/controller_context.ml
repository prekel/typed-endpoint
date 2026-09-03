open! Base
open Typed_endpoint

module Make (B : Backend.S) = struct
  module Endpoint = Typed_endpoint.Make (B)
  open Endpoint
  open Dsl

  let oauth =
    Security.Scheme.oauth2_implicit
      ~name:"petstore_auth"
      ~authorization_url:"https://petstore3.swagger.io/oauth/authorize"
      ~scopes:
        [ "write:pets", "modify pets in your account"; "read:pets", "read your pets" ]
      ~description:"Petstore OAuth implicit flow"
      ()
  ;;

  let api_key =
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

  let oauth_access =
    { bearer = true
    ; api_key = false
    ; security = [ Security.require ~scopes:[ "write:pets"; "read:pets" ] oauth ]
    }
  ;;

  let api_key_access =
    { bearer = false; api_key = true; security = [ Security.require api_key ] }
  ;;

  let pet_lookup_access =
    { bearer = true
    ; api_key = true
    ; security =
        [ Security.require api_key
        ; Security.require ~scopes:[ "write:pets"; "read:pets" ] oauth
        ]
    }
  ;;

  let authorize ~auth access =
    Guard.v
      ~security:access.security
      ~status:`Unauthorized
      ~response:(Response.json (module Dto.Api_response))
      ~check:(fun request ->
        let bearer = B.header request "authorization" in
        let key = B.header request "api_key" in
        let bearer_valid =
          access.bearer
          && Option.value_map
               bearer
               ~default:false
               ~f:(String.equal ("Bearer " ^ auth.Auth.bearer_token))
        in
        let key_valid =
          access.api_key
          && Option.value_map key ~default:false ~f:(String.equal auth.api_key)
        in
        B.Io.return
          (if bearer_valid || key_valid then
             Ok ()
           else
             Error
               Dto.Api_response.
                 { code = 401; type_ = "unauthorized"; message = "invalid credentials" }))
      ()
  ;;

  let secured ~auth ~access dependency =
    let open Context.Applicative_infix in
    authorize ~auth access *> Dependency.value dependency
  ;;

  let pet_oauth ~auth dependency = secured ~auth ~access:oauth_access dependency
  let pet_lookup ~auth dependency = secured ~auth ~access:pet_lookup_access dependency
  let api_key ~auth dependency = secured ~auth ~access:api_key_access dependency
  let public dependency = Dependency.value dependency

  let decode_errors =
    Decode_error_response.json
      ~payload:(module Dto.Api_response)
      ~map:Dto.Api_response.of_decode_error
  ;;
end
