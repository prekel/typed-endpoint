open! Base
open Typed_endpoint

module Make (B : Backend.S) (Users : User_service.S with type 'a io = 'a B.io) = struct
  module Common = Controller_context.Make (B)
  module Endpoint = Common.Endpoint
  module Io = B.Io
  open Io.Let_syntax
  open Endpoint
  open Dsl

  let unavailable error =
    Code_5xx (`Service_unavailable, Dto.Api_response.persistence_error error)
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
         |+ code4xx [ `Conflict ] (Response.json (module Dto.Api_response))
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun database user ->
    match Dto.User.to_domain user with
    | Error message -> Io.return (Bad_request (Dto.Api_response.bad_request message))
    | Ok user ->
      let%map result = Users.add ~database user in
      (match result with
       | Ok user -> OK (Dto.User.of_domain user)
       | Error (`Already_exists username) ->
         Code_4xx (`Conflict, Dto.Api_response.user_conflict username)
       | Error (`Persistence error) -> unavailable error)
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
         |+ code4xx [ `Conflict ] (Response.json (module Dto.Api_response))
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun database users ->
    match Dto.User_list.to_domain users with
    | Error message -> Io.return (Bad_request (Dto.Api_response.bad_request message))
    | Ok [] ->
      Io.return
        (Bad_request (Dto.Api_response.bad_request "at least one user is required"))
    | Ok users ->
      let%map result = Users.add_many ~database users in
      (match result with
       | Ok users -> OK (Dto.User.of_domain (List.last_exn users))
       | Error (`Already_exists username) ->
         Code_4xx (`Conflict, Dto.Api_response.user_conflict username)
       | Error (`Persistence error) -> unavailable error)
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
         / query "username" (module Http_parameter.Username)
         / query "password" (module Http_parameter.Password)
         /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Login_token)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun username password database () ->
    match username, password with
    | Some username, Some password ->
      let%map result = Users.authenticate ~database ~username ~password in
      (match result with
       | Ok true -> OK (username ^ "-session-token")
       | Ok false ->
         Bad_request (Dto.Api_response.bad_request "invalid username or password")
       | Error error -> unavailable error)
    | _ ->
      Io.return
        (Bad_request (Dto.Api_response.bad_request "invalid username or password"))
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
    @@ fun _database () -> Io.return (OK ())
  ;;

  let get_user =
    make_in_group
      ~meth:B.get
      ~operation_id:"getUserByName"
      ~summary:"Get user by user name."
      ~description:"Returns one user by username."
      ~path:(s "user" / param "username" (module Http_parameter.Username) /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.User)
         |+ JSON.not_found (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun username database () ->
    let%map result = Users.find ~database username in
    match result with
    | Ok (Some user) -> OK (Dto.User.of_domain user)
    | Ok None -> Not_found (Dto.Api_response.user_not_found username)
    | Error error -> unavailable error
  ;;

  let update_user =
    make_in_group
      ~meth:B.put
      ~operation_id:"updateUser"
      ~summary:"Update user resource."
      ~description:"Replaces the user selected by the path username."
      ~path:(s "user" / param "username" (module Http_parameter.Username) /? nil)
      ~request:(Request.json (module Dto.User))
      ~responses:
        (ok (Response.empty ~description:"Successful operation" ())
         |+ JSON.bad_request (module Dto.Api_response)
         |+ JSON.not_found (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun username database user ->
    match Dto.User.to_domain ~username user with
    | Error message -> Io.return (Bad_request (Dto.Api_response.bad_request message))
    | Ok user ->
      let%map result = Users.update ~database ~username user in
      (match result with
       | Ok _ -> OK ()
       | Error (`Not_found username) ->
         Not_found (Dto.Api_response.user_not_found username)
       | Error (`Persistence error) -> unavailable error)
  ;;

  let delete_user =
    make_in_group
      ~meth:B.delete
      ~operation_id:"deleteUser"
      ~summary:"Delete user resource."
      ~description:"Deletes the user selected by username."
      ~path:(s "user" / param "username" (module Http_parameter.Username) /? nil)
      ~request:Request.empty
      ~responses:
        (ok (Response.empty ~description:"User deleted" ())
         |+ JSON.not_found (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun username database () ->
    let%map result = Users.delete ~database username in
    match result with
    | Ok () -> OK ()
    | Error (`Not_found username) -> Not_found (Dto.Api_response.user_not_found username)
    | Error (`Persistence error) -> unavailable error
  ;;

  let groups ~database =
    [ Group.make_with_context
        ~context:(Common.public database)
        ~decode_error:Common.decode_errors
        ~tags:[ "user" ]
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
  ;;
end
