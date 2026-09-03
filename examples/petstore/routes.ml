open! Base
open Typed_endpoint

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
    ~title:"Swagger Petstore - OpenAPI 3.0"
    ~version:"1.0.29-SNAPSHOT"
    ~description:
      "A typed-endpoint implementation of the complete Swagger Petstore v3 route surface"
    ~servers:[ Openapi.Server.v ~url:"http://localhost:8080" () ]
    ()
;;

let swagger_ui_html =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Swagger Petstore</title>
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
    type t = int

    let of_string value =
      match Int.of_string_opt value with
      | Some id when id > 0 -> Ok id
      | _ -> Error "petId must be a positive integer"
    ;;

    let metadata : t Metadata.t =
      Metadata.v
        ~schema:
          (`Assoc
              [ "type", `String "integer"; "format", `String "int64"; "minimum", `Int 1 ])
        ~description:"ID of the pet"
        ()
    ;;
  end

  module Order_id = struct
    type t = int

    let of_string value =
      match Int.of_string_opt value with
      | Some id when id > 0 -> Ok id
      | _ -> Error "orderId must be a positive integer"
    ;;

    let metadata : t Metadata.t =
      Metadata.v
        ~schema:
          (`Assoc
              [ "type", `String "integer"; "format", `String "int64"; "minimum", `Int 1 ])
        ~description:"ID of the order"
        ()
    ;;
  end

  module Username = struct
    type t = string

    let of_string username =
      if String.is_empty (String.strip username) then
        Error "username must not be empty"
      else
        Ok username
    ;;

    let metadata : t Metadata.t =
      Metadata.v
        ~schema:(`Assoc [ "type", `String "string"; "minLength", `Int 1 ])
        ~description:"Petstore username"
        ()
    ;;
  end

  module Password = struct
    type t = string

    let of_string password =
      if String.is_empty password then
        Error "password must not be empty"
      else
        Ok password
    ;;

    let metadata : t Metadata.t =
      Metadata.v
        ~schema:(`Assoc [ "type", `String "string"; "minLength", `Int 1 ])
        ~description:"Password in clear text for this demo"
        ()
    ;;
  end

  module Pet_name = struct
    type t = string

    let of_string name =
      if String.is_empty (String.strip name) then
        Error "name must not be empty"
      else
        Ok name
    ;;

    let metadata : t Metadata.t =
      Metadata.v
        ~schema:(`Assoc [ "type", `String "string"; "minLength", `Int 1 ])
        ~description:"Updated pet name"
        ()
    ;;
  end

  let bounded_integer_schema ~maximum ~default =
    `Assoc
      [ "type", `String "integer"
      ; "minimum", `Int 1
      ; "maximum", `Int maximum
      ; "default", `Int default
      ]
  ;;

  module Page_query = struct
    type t = int

    let of_string value =
      match Int.of_string_opt value with
      | Some page when page >= 1 && page <= Domain.Page_request.max_page -> Ok page
      | _ ->
        Error ("page must be between 1 and " ^ Int.to_string Domain.Page_request.max_page)
    ;;

    let metadata : t Metadata.t =
      Metadata.v
        ~schema:
          (bounded_integer_schema
             ~maximum:Domain.Page_request.max_page
             ~default:Domain.Page_request.default_page)
        ~description:
          ("One-based page number; defaults to "
           ^ Int.to_string Domain.Page_request.default_page)
        ()
    ;;
  end

  module Limit_query = struct
    type t = int

    let of_string value =
      match Int.of_string_opt value with
      | Some limit when limit >= 1 && limit <= Domain.Page_request.max_limit -> Ok limit
      | _ ->
        Error
          ("limit must be between 1 and " ^ Int.to_string Domain.Page_request.max_limit)
    ;;

    let metadata : t Metadata.t =
      Metadata.v
        ~schema:
          (bounded_integer_schema
             ~maximum:Domain.Page_request.max_limit
             ~default:Domain.Page_request.default_limit)
        ~description:
          ("Page size; defaults to " ^ Int.to_string Domain.Page_request.default_limit)
        ()
    ;;
  end

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
               ~f:(String.equal ("Bearer " ^ auth.bearer_token))
        in
        let key_valid =
          access.api_key
          && Option.value_map key ~default:false ~f:(String.equal auth.api_key)
        in
        B.return
          (if bearer_valid || key_valid then
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

  let secured_context ~auth ~access services =
    let open Context.Applicative_infix in
    authorize ~auth access *> Dependency.value services
  ;;

  let public_context services = Dependency.value services

  let add_pet =
    make_in_group
      ~meth:B.post
      ~operation_id:"addPet"
      ~summary:"Add a new pet to the store."
      ~description:"Add a new pet to the store."
      ~path:(s "pet" /? nil)
      ~request:(Request.json (module Dto.Pet))
      ~responses:
        (JSON.ok (module Dto.Pet)
         |+ code4xx
              [ `Bad_request; `Conflict; `Unprocessable_entity ]
              (Response.json (module Dto.Api_response)))
    @@ fun services pet ->
    B.return
      (match Dto.Pet.to_domain pet with
       | Error message -> Code_4xx (`Bad_request, Dto.Api_response.bad_request message)
       | Ok (id, attributes) ->
         (match Pet_service.add (Services.pets services) ?id attributes with
          | Ok pet -> OK (Dto.Pet.of_domain pet)
          | Error (`Already_exists id) ->
            Code_4xx (`Conflict, Dto.Api_response.conflict id)))
  ;;

  let update_pet =
    make_in_group
      ~meth:B.put
      ~operation_id:"updatePet"
      ~summary:"Update an existing pet."
      ~description:"Update an existing pet by ID."
      ~path:(s "pet" /? nil)
      ~request:(Request.json (module Dto.Pet))
      ~responses:
        (JSON.ok (module Dto.Pet)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ JSON.not_found (module Dto.Api_response)
         |+ code4xx [ `Unprocessable_entity ] (Response.json (module Dto.Api_response)))
    @@ fun services pet ->
    B.return
      (match Dto.Pet.to_domain pet with
       | Error message -> Bad_request (Dto.Api_response.bad_request message)
       | Ok (None, _) -> Bad_request (Dto.Api_response.bad_request "id is required")
       | Ok (Some id, attributes) ->
         (match Pet_service.update (Services.pets services) ~id attributes with
          | Ok pet -> OK (Dto.Pet.of_domain pet)
          | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id)))
  ;;

  let find_by_status =
    make_in_group
      ~meth:B.get
      ~operation_id:"findPetsByStatus"
      ~summary:"Finds Pets by status."
      ~description:"Returns all pets having the requested official status."
      ~path:(s "pet" / s "findByStatus" / query_req "status" (module Dto.Status) /? nil)
      ~request:Request.empty
      ~responses:(JSON.ok (module Dto.Pet_list))
    @@ fun status services () ->
    Pet_service.list_by_status (Services.pets services) ~status |> Dto.Pet_list.of_domain
    |> fun pets -> B.return (OK pets)
  ;;

  let find_by_tags =
    make_in_group
      ~meth:B.get
      ~operation_id:"findPetsByTags"
      ~summary:"Finds Pets by tags."
      ~description:"Returns pets carrying at least one comma-separated tag."
      ~path:(s "pet" / s "findByTags" / query_req "tags" (module Dto.Tags) /? nil)
      ~request:Request.empty
      ~responses:(JSON.ok (module Dto.Pet_list))
    @@ fun tags services () ->
    Pet_service.list_by_tags (Services.pets services) ~tags |> Dto.Pet_list.of_domain
    |> fun pets -> B.return (OK pets)
  ;;

  let search_pets =
    make_in_group
      ~meth:B.get
      ~operation_id:"searchPets"
      ~summary:"Search pets with pagination."
      ~description:
        "Typed-endpoint extension retaining bounded pagination outside the official operations."
      ~path:
        (s "pet"
         / s "search"
         / query_req "status" (module Dto.Status)
         / query "page" (module Page_query)
         / query "limit" (module Limit_query)
         /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Pet_page) |+ JSON.bad_request (module Dto.Api_response))
    @@ fun status page limit services () ->
    let page = Option.value page ~default:Domain.Page_request.default_page in
    let limit = Option.value limit ~default:Domain.Page_request.default_limit in
    B.return
      (match Domain.Page_request.create ~page ~limit with
       | Error message -> Bad_request (Dto.Api_response.bad_request message)
       | Ok pagination ->
         Pet_service.find_by_status (Services.pets services) ~status ~pagination
         |> Dto.Pet_page.of_domain
         |> fun page -> OK page)
  ;;

  let get_pet =
    make_in_group
      ~meth:B.get
      ~operation_id:"getPetById"
      ~summary:"Find pet by ID."
      ~description:"Returns a single pet."
      ~path:(s "pet" / param "petId" (module Pet_id) /? nil)
      ~request:Request.empty
      ~responses:(JSON.ok (module Dto.Pet) |+ JSON.not_found (module Dto.Api_response))
    @@ fun id services () ->
    B.return
      (match Pet_service.find (Services.pets services) id with
       | Some pet -> OK (Dto.Pet.of_domain pet)
       | None -> Not_found (Dto.Api_response.not_found id))
  ;;

  let update_pet_with_form =
    make_in_group
      ~meth:B.post
      ~operation_id:"updatePetWithForm"
      ~summary:"Updates a pet in the store with form data."
      ~description:"Updates the pet name and/or status from query form fields."
      ~path:
        (s "pet"
         / param "petId" (module Pet_id)
         / query "name" (module Pet_name)
         / query "status" (module Dto.Status)
         /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Pet)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ JSON.not_found (module Dto.Api_response))
    @@ fun id name status services () ->
    B.return
      (match Pet_service.patch (Services.pets services) ~id ?name ?status () with
       | Ok pet -> OK (Dto.Pet.of_domain pet)
       | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id))
  ;;

  let delete_pet =
    make_in_group
      ~meth:B.delete
      ~operation_id:"deletePet"
      ~summary:"Deletes a pet."
      ~description:"Delete a pet."
      ~path:(s "pet" / param "petId" (module Pet_id) /? nil)
      ~request:Request.empty
      ~responses:
        (ok (Response.empty ~description:"Pet deleted" ())
         |+ JSON.not_found (module Dto.Api_response))
    @@ fun id services () ->
    B.return
      (match Pet_service.delete (Services.pets services) id with
       | Ok () -> OK ()
       | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id))
  ;;

  let upload_image =
    make_in_group
      ~meth:B.post
      ~operation_id:"uploadFile"
      ~summary:"Uploads an image."
      ~description:"Upload an opaque image of the pet."
      ~path:
        (s "pet"
         / param "petId" (module Pet_id)
         / s "uploadImage"
         / query
             "additionalMetadata"
             (Parameter.string ~description:"Additional metadata" ())
         /? nil)
      ~request:(Request.binary ~description:"Image bytes" ())
      ~responses:
        (JSON.ok (module Dto.Api_response)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ JSON.not_found (module Dto.Api_response))
    @@ fun id metadata services bytes ->
    B.return
      (match Pet_service.upload_image (Services.pets services) ~id ~metadata ~bytes with
       | Ok bytes -> OK (Dto.Api_response.upload_success ~id ~bytes ~metadata)
       | Error `Empty_file ->
         Bad_request (Dto.Api_response.bad_request "no file uploaded")
       | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id))
  ;;

  let get_inventory =
    make_in_group
      ~meth:B.get
      ~operation_id:"getInventory"
      ~summary:"Returns pet inventories by status."
      ~description:"Returns a map of status names to quantities."
      ~path:(s "store" / s "inventory" /? nil)
      ~request:Request.empty
      ~responses:(JSON.ok (module Dto.Inventory))
    @@ fun services () ->
    Pet_service.inventory (Services.pets services) |> Dto.Inventory.of_domain
    |> fun inventory -> B.return (OK inventory)
  ;;

  let place_order =
    make_in_group
      ~meth:B.post
      ~operation_id:"placeOrder"
      ~summary:"Place an order for a pet."
      ~description:"Place a new order in the store."
      ~path:(s "store" / s "order" /? nil)
      ~request:(Request.json (module Dto.Order))
      ~responses:
        (JSON.ok (module Dto.Order)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ code4xx [ `Unprocessable_entity ] (Response.json (module Dto.Api_response)))
    @@ fun services order ->
    B.return
      (match Dto.Order.to_domain order with
       | Error message -> Bad_request (Dto.Api_response.bad_request message)
       | Ok (_id, { pet_id = Some pet_id; _ })
         when Option.is_none (Pet_service.find (Services.pets services) pet_id) ->
         Bad_request (Dto.Api_response.bad_request "ordered pet does not exist")
       | Ok (id, attributes) ->
         (match Order_service.place (Services.orders services) ?id attributes with
          | Ok order -> OK (Dto.Order.of_domain order)
          | Error (`Already_exists id) ->
            Code_4xx
              ( `Unprocessable_entity
              , Dto.Api_response.bad_request
                  ("order " ^ Int.to_string id ^ " already exists") )))
  ;;

  let get_order =
    make_in_group
      ~meth:B.get
      ~operation_id:"getOrderById"
      ~summary:"Find purchase order by ID."
      ~description:"Returns a stored purchase order."
      ~path:(s "store" / s "order" / param "orderId" (module Order_id) /? nil)
      ~request:Request.empty
      ~responses:(JSON.ok (module Dto.Order) |+ JSON.not_found (module Dto.Api_response))
    @@ fun id services () ->
    B.return
      (match Order_service.find (Services.orders services) id with
       | Some order -> OK (Dto.Order.of_domain order)
       | None -> Not_found (Dto.Api_response.order_not_found id))
  ;;

  let delete_order =
    make_in_group
      ~meth:B.delete
      ~operation_id:"deleteOrder"
      ~summary:"Delete purchase order by identifier."
      ~description:"Deletes a stored purchase order."
      ~path:(s "store" / s "order" / param "orderId" (module Order_id) /? nil)
      ~request:Request.empty
      ~responses:
        (ok (Response.empty ~description:"Order deleted" ())
         |+ JSON.not_found (module Dto.Api_response))
    @@ fun id services () ->
    B.return
      (match Order_service.delete (Services.orders services) id with
       | Ok () -> OK ()
       | Error (`Not_found id) -> Not_found (Dto.Api_response.order_not_found id))
  ;;

  let create_user =
    make_in_group
      ~meth:B.post
      ~operation_id:"createUser"
      ~summary:"Create user."
      ~description:"Creates one Petstore user."
      ~path:(s "user" /? nil)
      ~request:(Request.json (module Dto.User))
      ~responses:
        (JSON.ok (module Dto.User)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ code4xx [ `Conflict ] (Response.json (module Dto.Api_response)))
    @@ fun services user ->
    B.return
      (match Dto.User.to_domain user with
       | Error message -> Bad_request (Dto.Api_response.bad_request message)
       | Ok user ->
         (match User_service.add (Services.users services) user with
          | Ok user -> OK (Dto.User.of_domain user)
          | Error (`Already_exists username) ->
            Code_4xx (`Conflict, Dto.Api_response.user_conflict username)))
  ;;

  let create_users_with_list =
    make_in_group
      ~meth:B.post
      ~operation_id:"createUsersWithListInput"
      ~summary:"Creates list of users with given input array."
      ~description:"Creates all users atomically and returns the final created user."
      ~path:(s "user" / s "createWithList" /? nil)
      ~request:(Request.json (module Dto.User_list))
      ~responses:
        (JSON.ok (module Dto.User)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ code4xx [ `Conflict ] (Response.json (module Dto.Api_response)))
    @@ fun services users ->
    B.return
      (match Dto.User_list.to_domain users with
       | Error message -> Bad_request (Dto.Api_response.bad_request message)
       | Ok [] ->
         Bad_request (Dto.Api_response.bad_request "at least one user is required")
       | Ok users ->
         (match User_service.add_many (Services.users services) users with
          | Ok users -> OK (Dto.User.of_domain (List.last_exn users))
          | Error (`Already_exists username) ->
            Code_4xx (`Conflict, Dto.Api_response.user_conflict username)))
  ;;

  let login_user =
    make_in_group
      ~meth:B.get
      ~operation_id:"loginUser"
      ~summary:"Logs user into the system."
      ~description:"Authenticates the demo user and returns a session token."
      ~path:
        (s "user"
         / s "login"
         / query "username" (module Username)
         / query "password" (module Password)
         /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Login_token) |+ JSON.bad_request (module Dto.Api_response))
    @@ fun username password services () ->
    B.return
      (match username, password with
       | Some username, Some password
         when User_service.authenticate (Services.users services) ~username ~password ->
         OK (username ^ "-session-token")
       | _ -> Bad_request (Dto.Api_response.bad_request "invalid username or password"))
  ;;

  let logout_user =
    make_in_group
      ~meth:B.get
      ~operation_id:"logoutUser"
      ~summary:"Logs out current logged in user session."
      ~description:"Ends the demo session."
      ~path:(s "user" / s "logout" /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.empty ~description:"Successful operation" ()))
    @@ fun _services () -> B.return (OK ())
  ;;

  let get_user =
    make_in_group
      ~meth:B.get
      ~operation_id:"getUserByName"
      ~summary:"Get user by user name."
      ~description:"Returns one user by username."
      ~path:(s "user" / param "username" (module Username) /? nil)
      ~request:Request.empty
      ~responses:(JSON.ok (module Dto.User) |+ JSON.not_found (module Dto.Api_response))
    @@ fun username services () ->
    B.return
      (match User_service.find (Services.users services) username with
       | Some user -> OK (Dto.User.of_domain user)
       | None -> Not_found (Dto.Api_response.user_not_found username))
  ;;

  let update_user =
    make_in_group
      ~meth:B.put
      ~operation_id:"updateUser"
      ~summary:"Update user resource."
      ~description:"Replaces the user selected by the path username."
      ~path:(s "user" / param "username" (module Username) /? nil)
      ~request:(Request.json (module Dto.User))
      ~responses:
        (ok (Response.empty ~description:"Successful operation" ())
         |+ JSON.bad_request (module Dto.Api_response)
         |+ JSON.not_found (module Dto.Api_response))
    @@ fun username services user ->
    B.return
      (match Dto.User.to_domain ~username user with
       | Error message -> Bad_request (Dto.Api_response.bad_request message)
       | Ok user ->
         (match User_service.update (Services.users services) ~username user with
          | Ok _ -> OK ()
          | Error (`Not_found username) ->
            Not_found (Dto.Api_response.user_not_found username)))
  ;;

  let delete_user =
    make_in_group
      ~meth:B.delete
      ~operation_id:"deleteUser"
      ~summary:"Delete user resource."
      ~description:"Deletes the user selected by username."
      ~path:(s "user" / param "username" (module Username) /? nil)
      ~request:Request.empty
      ~responses:
        (ok (Response.empty ~description:"User deleted" ())
         |+ JSON.not_found (module Dto.Api_response))
    @@ fun username services () ->
    B.return
      (match User_service.delete (Services.users services) username with
       | Ok () -> OK ()
       | Error (`Not_found username) ->
         Not_found (Dto.Api_response.user_not_found username))
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

  let compile ~auth services =
    let group ~context ~tag ~description routes =
      Group.make_with_context
        ~context
        ~decode_error:decode_errors
        ~tags:[ tag ]
        ~description
        routes
    in
    let public = public_context services in
    let pet_oauth = secured_context ~auth ~access:oauth_access services in
    let pet_lookup = secured_context ~auth ~access:pet_lookup_access services in
    let inventory_api_key = secured_context ~auth ~access:api_key_access services in
    let api =
      [ group
          ~context:pet_oauth
          ~tag:"pet"
          ~description:"Everything about your pets"
          [ add_pet
          ; update_pet
          ; find_by_status
          ; find_by_tags
          ; search_pets
          ; update_pet_with_form
          ; delete_pet
          ; upload_image
          ]
      ; group
          ~context:pet_lookup
          ~tag:"pet"
          ~description:"Pet lookup accepting the official alternative credentials"
          [ get_pet ]
      ; group
          ~context:inventory_api_key
          ~tag:"store"
          ~description:"Access to Petstore inventory"
          [ get_inventory ]
      ; group
          ~context:public
          ~tag:"store"
          ~description:"Access to Petstore orders"
          [ place_order; get_order; delete_order ]
      ; group
          ~context:public
          ~tag:"user"
          ~description:"Operations about users"
          [ create_user
          ; create_users_with_list
          ; login_user
          ; logout_user
          ; get_user
          ; update_user
          ; delete_user
          ]
      ]
    in
    let compiled = compile_exn api in
    let runtime =
      Group.make
        ~description:"Runtime endpoints"
        [ openapi_route compiled; swagger_ui "/docs"; swagger_ui "/docs/"; health ]
    in
    compile_exn (api @ [ runtime ])
  ;;
end
