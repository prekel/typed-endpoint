open! Base
module Petstore_principal = Principal
open Typed_endpoint

module Make
    (B : Backend.S)
    (Users : User_service.S with type 'a io = 'a B.io)
    (Sessions :
       Session_service.S with type 'a io = 'a B.io and type database = Users.database) =
struct
  module Common = Controller_context.Make (B) (Sessions)
  module Endpoint = Common.Endpoint
  module Io = B.Io
  open Io.Let_syntax
  open Endpoint

  let unavailable
        (response_case : ([ `Service_unavailable ], Dto.Api_response.t) Response.case)
        error
    =
    respond response_case (Dto.Api_response.persistence_error error)
  ;;

  let create_user =
    post / "user"
    |> documented
         ~operation_id:"createUser"
         ~summary:"Create user."
         ~description:"Creates one Petstore user."
    |> accepts (Request.json (module Dto.User_create))
    |> returns
         (case `OK (Response.json (module Dto.User))
          <|> case
                `Bad_request
                (Response.json ~description:"Invalid request" (module Dto.Api_response))
          <|> case
                `Conflict
                (Response.json
                   ~description:"Username already exists"
                   (module Dto.Api_response))
          <|> case
                `Service_unavailable
                (Response.json
                   ~description:"Service temporarily unavailable"
                   (module Dto.Api_response)))
    ==> fun ok bad_request conflict service_unavailable database body ->
    let%bind user = Request_body.read body in
    match user with
    | Error error -> Request_body.reject error
    | Ok user ->
      (match Dto.User_create.to_domain user with
       | Error message -> respond bad_request (Dto.Api_response.bad_request message)
       | Ok user ->
         let%bind result = Users.add ~database user in
         (match result with
          | Ok user -> respond ok (Dto.User.of_domain user)
          | Error (`Already_exists username) ->
            respond conflict (Dto.Api_response.user_conflict username)
          | Error (`Persistence error) -> unavailable service_unavailable error))
  ;;

  let create_users ~path ~operation_id =
    post / "user" / path
    |> documented
         ~operation_id
         ~summary:"Creates list of users with given input array."
         ~description:
           "Creates all users atomically and returns all created users in request order."
    |> accepts (Request.json (module Dto.User_create_list))
    |> returns
         (case `OK (Response.json (module Dto.User_list))
          <|> case
                `Forbidden
                (Response.json
                   ~description:"Insufficient permissions"
                   (module Dto.Api_response))
          <|> case
                `Bad_request
                (Response.json ~description:"Invalid request" (module Dto.Api_response))
          <|> case
                `Conflict
                (Response.json
                   ~description:"Username already exists"
                   (module Dto.Api_response))
          <|> case
                `Service_unavailable
                (Response.json
                   ~description:"Service temporarily unavailable"
                   (module Dto.Api_response)))
    ==> fun ok forbidden bad_request conflict service_unavailable context body ->
    let database = Common.Secured.dependency context in
    let actor = Petstore_principal.actor (Common.Secured.principal context) in
    let%bind users = Request_body.read body in
    match users with
    | Error error -> Request_body.reject error
    | Ok users ->
      (match Dto.User_create_list.to_domain users with
       | Error message -> respond bad_request (Dto.Api_response.bad_request message)
       | Ok [] ->
         respond
           bad_request
           (Dto.Api_response.bad_request "at least one user is required")
       | Ok users ->
         let%bind result = Users.add_many ~database ~actor users in
         (match result with
          | Ok users -> respond ok (Dto.User_list.of_domain users)
          | Error `Forbidden -> respond forbidden (Dto.Api_response.forbidden ())
          | Error (`Already_exists username) ->
            respond conflict (Dto.Api_response.user_conflict username)
          | Error (`Persistence error) -> unavailable service_unavailable error))
  ;;

  let login_user =
    post / "user" / "login"
    |> documented
         ~operation_id:"loginUser"
         ~summary:"Logs user into the system."
         ~description:"Authenticates a user and creates an independent one-hour session."
    |> accepts (Request.json (module Dto.Login_request))
    |> returns
         (case `OK (Response.json (module Dto.Login_token))
          <|> case
                `Bad_request
                (Response.json
                   ~description:"Invalid request or credentials"
                   (module Dto.Api_response))
          <|> case
                `Service_unavailable
                (Response.json
                   ~description:"Service temporarily unavailable"
                   (module Dto.Api_response)))
    ==> fun ok bad_request service_unavailable database body ->
    let%bind credentials = Request_body.read body in
    match credentials with
    | Error error -> Request_body.reject error
    | Ok { username; password = _ } when String.is_empty (String.strip username) ->
      respond bad_request (Dto.Api_response.bad_request "username must not be empty")
    | Ok { username; password } ->
      let%bind result = Sessions.login ~database ~username ~password in
      (match result with
       | Ok (Some session) -> respond ok session.token
       | Ok None ->
         respond bad_request (Dto.Api_response.bad_request "invalid username or password")
       | Error error -> unavailable service_unavailable error)
  ;;

  let logout_user =
    post / "user" / "logout"
    |> documented
         ~operation_id:"logoutUser"
         ~summary:"Logs out the current session."
         ~description:
           "Revokes the presented session. The independent demo bearer returns 200 without revocation."
    |> accepts Request.empty
    |> returns
         (case `OK (Response.empty ~description:"Successful operation" ())
          <|> case
                `Unauthorized
                (Response.json
                   ~description:"Authentication required"
                   (module Dto.Api_response))
          <|> case
                `Service_unavailable
                (Response.json
                   ~description:"Service temporarily unavailable"
                   (module Dto.Api_response)))
    ==> fun ok unauthorized service_unavailable context () ->
    let identity = Typed_endpoint.Principal.identity (Common.Secured.principal context) in
    match identity.session_id with
    | None -> respond ok ()
    | Some token ->
      let database = Common.Secured.dependency context in
      let%bind result = Sessions.logout ~database token in
      (match result with
       | Ok true -> respond ok ()
       | Ok false ->
         respond
           unauthorized
           Dto.Api_response.
             { code = 401; type_ = "unauthorized"; message = "invalid credentials" }
       | Error error -> unavailable service_unavailable error)
  ;;

  let get_user =
    get / "user" /: arg "username" (module Http_parameter.Username)
    |> documented
         ~operation_id:"getUserByName"
         ~summary:"Get user by user name."
         ~description:"Returns one user by username."
    |> accepts Request.empty
    |> returns
         (case `OK (Response.json (module Dto.User))
          <|> case
                `Not_found
                (Response.json ~description:"User not found" (module Dto.Api_response))
          <|> case
                `Service_unavailable
                (Response.json
                   ~description:"Service temporarily unavailable"
                   (module Dto.Api_response)))
    ==> fun username ok not_found service_unavailable database () ->
    let%bind result = Users.find ~database username in
    match result with
    | Ok (Some user) -> respond ok (Dto.User.of_domain user)
    | Ok None -> respond not_found (Dto.Api_response.user_not_found username)
    | Error error -> unavailable service_unavailable error
  ;;

  let update_user =
    put / "user" /: arg "username" (module Http_parameter.Username)
    |> documented
         ~operation_id:"updateUser"
         ~summary:"Update user resource."
         ~description:"Replaces the user selected by the path username."
    |> accepts (Request.json (module Dto.User_update))
    |> returns
         (case `OK (Response.empty ~description:"Successful operation" ())
          <|> case
                `Forbidden
                (Response.json
                   ~description:"Insufficient permissions"
                   (module Dto.Api_response))
          <|> case
                `Bad_request
                (Response.json ~description:"Invalid request" (module Dto.Api_response))
          <|> case
                `Not_found
                (Response.json ~description:"User not found" (module Dto.Api_response))
          <|> case
                `Service_unavailable
                (Response.json
                   ~description:"Service temporarily unavailable"
                   (module Dto.Api_response)))
    ==>
    fun username ok forbidden bad_request not_found service_unavailable context body ->
    let database = Common.Secured.dependency context in
    let actor = Petstore_principal.actor (Common.Secured.principal context) in
    let%bind user = Request_body.read body in
    match user with
    | Error error -> Request_body.reject error
    | Ok user ->
      (match Dto.User_update.to_domain ~username user with
       | Error message -> respond bad_request (Dto.Api_response.bad_request message)
       | Ok user ->
         let%bind result = Users.update ~database ~actor ~username user in
         (match result with
          | Ok _ -> respond ok ()
          | Error `Forbidden -> respond forbidden (Dto.Api_response.forbidden ())
          | Error (`Not_found username) ->
            respond not_found (Dto.Api_response.user_not_found username)
          | Error (`Persistence error) -> unavailable service_unavailable error))
  ;;

  let delete_user =
    delete / "user" /: arg "username" (module Http_parameter.Username)
    |> documented
         ~operation_id:"deleteUser"
         ~summary:"Delete user resource."
         ~description:"Deletes the user selected by username."
    |> accepts Request.empty
    |> returns
         (case `OK (Response.empty ~description:"User deleted" ())
          <|> case
                `Forbidden
                (Response.json
                   ~description:"Insufficient permissions"
                   (module Dto.Api_response))
          <|> case
                `Not_found
                (Response.json ~description:"User not found" (module Dto.Api_response))
          <|> case
                `Service_unavailable
                (Response.json
                   ~description:"Service temporarily unavailable"
                   (module Dto.Api_response)))
    ==> fun username ok forbidden not_found service_unavailable context () ->
    let database = Common.Secured.dependency context in
    let actor = Petstore_principal.actor (Common.Secured.principal context) in
    let%bind result = Users.delete ~database ~actor username in
    match result with
    | Ok () -> respond ok ()
    | Error `Forbidden -> respond forbidden (Dto.Api_response.forbidden ())
    | Error (`Not_found username) ->
      respond not_found (Dto.Api_response.user_not_found username)
    | Error (`Persistence error) -> unavailable service_unavailable error
  ;;

  let groups ~auth ~database =
    [ Group.make_with_context
        ~context:(Common.public database)
        ~decode_error:Common.decode_errors
        ~tags:[ "user" ]
        ~description:"Operations about users"
        [ create_user; login_user; get_user ]
    ; Group.make_with_context
        ~context:(Common.management ~auth database)
        ~decode_error:Common.decode_errors
        ~tags:[ "user" ]
        ~description:"User management with ownership and administrative checks"
        [ create_users ~path:"createWithList" ~operation_id:"createUsersWithListInput"
        ; create_users ~path:"createWithArray" ~operation_id:"createUsersWithArrayInput"
        ; update_user
        ; delete_user
        ]
    ; Group.make_with_context
        ~context:(Common.session ~auth database)
        ~decode_error:Common.decode_errors
        ~tags:[ "user" ]
        ~description:"Session logout"
        [ logout_user ]
    ]
  ;;
end
