open! Base
open Typed_endpoint
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson

type auth =
  { bearer_token : string
  ; api_key : string
  }

let getenv_or_default name default = Stdlib.Sys.getenv_opt name |> Option.value ~default

let auth_from_env () =
  { bearer_token = getenv_or_default "PETSTORE_BEARER_TOKEN" "demo-token"
  ; api_key = getenv_or_default "PETSTORE_API_KEY" "demo-key"
  }
;;

let openapi_config =
  Openapi.Config.v
    ~title:"Typed Petstore"
    ~version:"1.0.0"
    ~description:"A typed-endpoint subset of Swagger Petstore v3"
    ~servers:[ Openapi.Server.v ~url:"http://localhost:8080" () ]
    ()
;;

let swagger_ui_html =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Typed Petstore API</title>
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.32.14/swagger-ui.css">
    <style>html { box-sizing: border-box; overflow-y: scroll; } body { margin: 0; background: #fafafa; }</style>
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5.32.14/swagger-ui-bundle.js" crossorigin="anonymous"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5.32.14/swagger-ui-standalone-preset.js" crossorigin="anonymous"></script>
    <script>
      window.onload = function () {
        SwaggerUIBundle({
          url: "/openapi.json",
          dom_id: "#swagger-ui",
          deepLinking: true,
          persistAuthorization: true,
          presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
          layout: "StandaloneLayout"
        });
      };
    </script>
  </body>
</html>
|}
;;

module Make (B : Backend.S) = struct
  module Endpoint = Typed_endpoint.Make (B)
  open Endpoint
  open Dsl

  module Pet_id = struct
    type t = int [@@deriving jsonschema]

    let of_string value =
      try Ok (Int.of_string value) with
      | _ -> Error "petId must be an integer"
    ;;

    let metadata : t Metadata.t =
      Metadata.v ~schema:t_jsonschema ~description:"Pet identifier" ()
    ;;
  end

  module Status = struct
    type t = string [@@deriving jsonschema]

    let of_string = function
      | ("available" | "pending" | "sold") as status -> Ok status
      | _ -> Error "status must be available, pending, or sold"
    ;;

    let metadata : t Metadata.t =
      Metadata.v ~schema:t_jsonschema ~description:"Pet status" ()
    ;;
  end

  let oauth =
    Security.Scheme.oauth2_implicit
      ~name:"petstore_auth"
      ~authorization_url:"https://example.invalid/oauth/authorize"
      ~scopes:
        [ "write:pets", "modify pets in your account"; "read:pets", "read your pets" ]
      ~description:"OAuth bearer token"
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

  let authorize ~auth ~scope =
    Guard.v
      ~security:[ Security.require ~scopes:[ scope ] oauth; Security.require api_key ]
      ~status:`Unauthorized
      ~response:(Response.json (module Dto.Api_response))
      ~check:(fun request ->
        let bearer = B.header request "authorization" in
        let key = B.header request "api_key" in
        let authorized =
          Option.value_map
            bearer
            ~default:false
            ~f:(String.equal ("Bearer " ^ auth.bearer_token))
          || Option.value_map key ~default:false ~f:(String.equal auth.api_key)
        in
        B.return
          (if authorized then
             Ok ()
           else
             Error
               Dto.Api_response.
                 { code = 401; type_ = "unauthorized"; message = "invalid credentials" }))
      ()
  ;;

  let decode_errors =
    Decode_error_response.json
      ~payload:(module Dto.Api_response)
      ~map:Dto.Api_response.of_decode_error
  ;;

  let context ~auth ~scope service =
    Context.map (Context.both (authorize ~auth ~scope) (Dependency.value service)) ~f:snd
  ;;

  let add_pet ~auth service =
    make_with
      ~context:(context ~auth ~scope:"write:pets" service)
      ~meth:B.post
      ~operation_id:"addPet"
      ~description:"Add a new pet to the store"
      ~path:(s "pet" /? nil)
      ~request:(Request.json (module Dto.Pet))
      ~responses:(ok (Response.json (module Dto.Pet)))
    @@ fun service pet -> B.return (OK (Pet_service.add service pet))
  ;;

  let update_pet ~auth service =
    make_with
      ~context:(context ~auth ~scope:"write:pets" service)
      ~meth:B.put
      ~operation_id:"updatePet"
      ~description:"Update an existing pet"
      ~path:(s "pet" /? nil)
      ~request:(Request.json (module Dto.Pet))
      ~responses:
        (ok (Response.json (module Dto.Pet))
         |+ code4xx [ `Bad_request; `Not_found ] (Response.json (module Dto.Api_response))
        )
    @@ fun service pet ->
    B.return
      (match Pet_service.update service pet with
       | Ok pet -> OK pet
       | Error error ->
         Code_4xx
           ( (if Int.equal error.code 404 then
                `Not_found
              else
                `Bad_request)
           , error ))
  ;;

  let find_by_status ~auth service =
    make_with
      ~context:(context ~auth ~scope:"read:pets" service)
      ~meth:B.get
      ~operation_id:"findPetsByStatus"
      ~description:"Find pets by status"
      ~path:(s "pet" / s "findByStatus" / query_req "status" (module Status) /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.json (module Dto.Pet_list)))
    @@ fun status service () -> B.return (OK (Pet_service.find_by_status service status))
  ;;

  let get_pet ~auth service =
    make_with
      ~context:(context ~auth ~scope:"read:pets" service)
      ~meth:B.get
      ~operation_id:"getPetById"
      ~description:"Find pet by ID"
      ~path:(s "pet" / param "petId" (module Pet_id) /? nil)
      ~request:Request.empty
      ~responses:
        (ok (Response.json (module Dto.Pet))
         |+ not_found (Response.json (module Dto.Api_response)))
    @@ fun id service () ->
    B.return
      (match Pet_service.find service id with
       | Some pet -> OK pet
       | None -> Not_found (Dto.Api_response.not_found id))
  ;;

  let delete_pet ~auth service =
    make_with
      ~context:(context ~auth ~scope:"write:pets" service)
      ~meth:B.delete
      ~operation_id:"deletePet"
      ~description:"Delete a pet"
      ~path:(s "pet" / param "petId" (module Pet_id) /? nil)
      ~request:Request.empty
      ~responses:
        (no_content ~description:"Pet deleted"
         |+ not_found (Response.json (module Dto.Api_response)))
    @@ fun id service () ->
    B.return
      (match Pet_service.delete service id with
       | Ok () -> No_content
       | Error error -> Not_found error)
  ;;

  let openapi_route compiled =
    Unsafe.route ~meth:B.get ~path:"/openapi.json" ~handler:(fun _request ->
      B.respond_json (Compiled.openapi ~config:openapi_config compiled))
  ;;

  let swagger_ui path =
    Unsafe.route ~meth:B.get ~path ~handler:(fun _request ->
      B.respond_html swagger_ui_html)
  ;;

  let health =
    Unsafe.route ~meth:B.get ~path:"/health" ~handler:(fun _request ->
      B.respond_json (`Assoc [ "status", `String "ok" ]))
  ;;

  let compile ~auth service =
    let routes =
      [ add_pet ~auth service
      ; update_pet ~auth service
      ; find_by_status ~auth service
      ; get_pet ~auth service
      ; delete_pet ~auth service
      ]
    in
    let api =
      Group.v
        ~decode_error:decode_errors
        ~metadata:
          (Operation_metadata.v
             ~tags:[ "pet" ]
             ~description:"Everything about your pets"
             ())
        routes
    in
    let compiled = compile_exn [ api ] in
    let runtime =
      Group.v
        ~metadata:(Operation_metadata.v ~description:"Runtime endpoints" ())
        [ openapi_route compiled; swagger_ui "/docs"; swagger_ui "/docs/"; health ]
    in
    compile_exn [ api; runtime ]
  ;;
end
