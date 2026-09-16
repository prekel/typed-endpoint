open! Base
open Typed_endpoint

module Make (B : Backend.S) (Users : User_service.S with type 'a io = 'a B.io) = struct
  module Common = Controller_context.Make (B)
  module Endpoint = Common.Endpoint
  module Io = B.Io
  open Io.Let_syntax
  open Endpoint

  let rate_limit_header =
    Header.required
      "X-Rate-Limit"
      (Header.int ~description:"Maximum requests allowed during the current window" ())
  ;;

  let expires_after_header =
    Header.required
      "X-Expires-After"
      (Header.v
         ~schema:(Json_schema.string_exn ~format:`Date_time ())
         ~description:"UTC time at which the current rate-limit window expires"
         ~of_string:(fun value -> Ok value)
         ~to_string:Fn.id
         ())
  ;;

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
    |> accepts (Request.json (module Dto.User))
    |> returns
         (case `OK (Response.json (module Dto.User))
          <|> case `Bad_request (Response.json (module Dto.Api_response))
          <|> case `Conflict (Response.json (module Dto.Api_response))
          <|> case `Service_unavailable (Response.json (module Dto.Api_response)))
    ==> fun ok bad_request conflict service_unavailable database user ->
    match Dto.User.to_domain user with
    | Error message -> respond bad_request (Dto.Api_response.bad_request message)
    | Ok user ->
      let%bind result = Users.add ~database user in
      (match result with
       | Ok user -> respond ok (Dto.User.of_domain user)
       | Error (`Already_exists username) ->
         respond conflict (Dto.Api_response.user_conflict username)
       | Error (`Persistence error) -> unavailable service_unavailable error)
  ;;

  let create_users_with_list =
    post / "user" / "createWithList"
    |> documented
         ~operation_id:"createUsersWithListInput"
         ~summary:"Creates list of users with given input array."
         ~description:"Creates all users atomically and returns the final created user."
    |> accepts (Request.json (module Dto.User_list))
    |> returns
         (case `OK (Response.json (module Dto.User))
          <|> case `Bad_request (Response.json (module Dto.Api_response))
          <|> case `Conflict (Response.json (module Dto.Api_response))
          <|> case `Service_unavailable (Response.json (module Dto.Api_response)))
    ==> fun ok bad_request conflict service_unavailable database users ->
    match Dto.User_list.to_domain users with
    | Error message -> respond bad_request (Dto.Api_response.bad_request message)
    | Ok [] ->
      respond bad_request (Dto.Api_response.bad_request "at least one user is required")
    | Ok users ->
      let%bind result = Users.add_many ~database users in
      (match result with
       | Ok users -> respond ok (Dto.User.of_domain (List.last_exn users))
       | Error (`Already_exists username) ->
         respond conflict (Dto.Api_response.user_conflict username)
       | Error (`Persistence error) -> unavailable service_unavailable error)
  ;;

  let login_user =
    get
    / "user"
    / "login"
    /? arg "username" (module Http_parameter.Username)
    /? arg "password" (module Http_parameter.Password)
    |> documented
         ~operation_id:"loginUser"
         ~summary:"Logs user into the system."
         ~description:"Authenticates the demo user and returns a session token."
    |> accepts Request.empty
    |> returns
         (case
            `OK
            (Response.json (module Dto.Login_token)
             |> Response.with_header expires_after_header
             |> Response.with_header rate_limit_header)
          <|> case `Bad_request (Response.json (module Dto.Api_response))
          <|> case `Service_unavailable (Response.json (module Dto.Api_response)))
    ==> fun username password ok bad_request service_unavailable database () ->
    match username, password with
    | Some username, Some password ->
      let%bind result = Users.authenticate ~database ~username ~password in
      (match result with
       | Ok true ->
         respond ok (1000, ("2030-01-01T00:00:00Z", username ^ "-session-token"))
       | Ok false ->
         respond bad_request (Dto.Api_response.bad_request "invalid username or password")
       | Error error -> unavailable service_unavailable error)
    | _ ->
      respond bad_request (Dto.Api_response.bad_request "invalid username or password")
  ;;

  let logout_user =
    get / "user" / "logout"
    |> documented
         ~operation_id:"logoutUser"
         ~summary:"Logs out current logged in user session."
         ~description:"Ends the demo session."
    |> accepts Request.empty
    |> returns (case `OK (Response.empty ~description:"Successful operation" ()))
    ==> fun ok _database () -> respond ok ()
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
          <|> case `Not_found (Response.json (module Dto.Api_response))
          <|> case `Service_unavailable (Response.json (module Dto.Api_response)))
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
    |> accepts (Request.json (module Dto.User))
    |> returns
         (case `OK (Response.empty ~description:"Successful operation" ())
          <|> case `Bad_request (Response.json (module Dto.Api_response))
          <|> case `Not_found (Response.json (module Dto.Api_response))
          <|> case `Service_unavailable (Response.json (module Dto.Api_response)))
    ==> fun username ok bad_request not_found service_unavailable database user ->
    match Dto.User.to_domain ~username user with
    | Error message -> respond bad_request (Dto.Api_response.bad_request message)
    | Ok user ->
      let%bind result = Users.update ~database ~username user in
      (match result with
       | Ok _ -> respond ok ()
       | Error (`Not_found username) ->
         respond not_found (Dto.Api_response.user_not_found username)
       | Error (`Persistence error) -> unavailable service_unavailable error)
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
          <|> case `Not_found (Response.json (module Dto.Api_response))
          <|> case `Service_unavailable (Response.json (module Dto.Api_response)))
    ==> fun username ok not_found service_unavailable database () ->
    let%bind result = Users.delete ~database username in
    match result with
    | Ok () -> respond ok ()
    | Error (`Not_found username) ->
      respond not_found (Dto.Api_response.user_not_found username)
    | Error (`Persistence error) -> unavailable service_unavailable error
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
