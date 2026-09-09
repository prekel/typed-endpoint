open! Base
open Typed_endpoint

module Pet_id = struct
  type t = int

  let of_string value =
    match Int.of_string_opt value with
    | Some id when id > 0 -> Ok id
    | _ -> Error "petId must be a positive integer"
  ;;

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:(Json_schema.integer_exn ~format:`Int64 ~minimum:1 ())
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
      ~schema:(Json_schema.integer_exn ~format:`Int64 ~minimum:1 ())
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
      ~schema:(Json_schema.string_exn ~min_length:1 ())
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
      ~schema:(Json_schema.string_exn ~min_length:1 ())
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
      ~schema:(Json_schema.string_exn ~min_length:1 ())
      ~description:"Updated pet name"
      ()
  ;;
end

let bounded_integer_schema ~maximum ~default =
  Json_schema.integer_exn ~minimum:1 ~maximum ~default ()
;;

module Page = struct
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

module Limit = struct
  type t = int

  let of_string value =
    match Int.of_string_opt value with
    | Some limit when limit >= 1 && limit <= Domain.Page_request.max_limit -> Ok limit
    | _ ->
      Error ("limit must be between 1 and " ^ Int.to_string Domain.Page_request.max_limit)
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
