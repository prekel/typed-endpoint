open! Base
open Typed_endpoint

module Decimal_int =
  (val Parameter.int ~description:"Decimal integer" () : Parameter.S with type t = int)

module Pet_id = struct
  type t = int

  let of_string value =
    match Result.ok (Decimal_int.of_string value) with
    | Some id when id > 0 -> Ok id
    | _ -> Error "petId must be a positive integer"
  ;;

  let t_jsonschema : t Json_schema.t =
    Json_schema.with_openapi
      ~description:"ID of the pet"
      (Json_schema.integer ~format:`Int64 ~minimum:1 ~maximum:Int.max_value ())
  ;;
end

module Order_id = struct
  type t = int

  let of_string value =
    match Result.ok (Decimal_int.of_string value) with
    | Some id when id > 0 -> Ok id
    | _ -> Error "orderId must be a positive integer"
  ;;

  let t_jsonschema : t Json_schema.t =
    Json_schema.with_openapi
      ~description:"ID of the order"
      (Json_schema.integer ~format:`Int64 ~minimum:1 ~maximum:Int.max_value ())
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

  let t_jsonschema : t Json_schema.t =
    Json_schema.with_openapi
      ~description:"Petstore username"
      (Json_schema.string ~min_length:1 ())
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

  let t_jsonschema : t Json_schema.t =
    Json_schema.with_openapi
      ~description:"Password in clear text for this demo"
      (Json_schema.string ~min_length:1 ())
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

  let t_jsonschema : t Json_schema.t =
    Json_schema.with_openapi
      ~description:"Updated pet name"
      (Json_schema.string ~min_length:1 ())
  ;;
end

let bounded_integer_schema ~maximum ~default =
  Json_schema.integer ~minimum:1 ~maximum ~default ()
;;

module Page = struct
  type t = int

  let of_string value =
    match Result.ok (Decimal_int.of_string value) with
    | Some page when page >= 1 && page <= Domain.Page_request.max_page -> Ok page
    | _ ->
      Error ("page must be between 1 and " ^ Int.to_string Domain.Page_request.max_page)
  ;;

  let t_jsonschema : t Json_schema.t =
    Json_schema.with_openapi
      ~description:
        ("One-based page number; defaults to "
         ^ Int.to_string Domain.Page_request.default_page)
      (bounded_integer_schema
         ~maximum:Domain.Page_request.max_page
         ~default:Domain.Page_request.default_page)
  ;;
end

module Limit = struct
  type t = int

  let of_string value =
    match Result.ok (Decimal_int.of_string value) with
    | Some limit when limit >= 1 && limit <= Domain.Page_request.max_limit -> Ok limit
    | _ ->
      Error ("limit must be between 1 and " ^ Int.to_string Domain.Page_request.max_limit)
  ;;

  let t_jsonschema : t Json_schema.t =
    Json_schema.with_openapi
      ~description:
        ("Page size; defaults to " ^ Int.to_string Domain.Page_request.default_limit)
      (bounded_integer_schema
         ~maximum:Domain.Page_request.max_limit
         ~default:Domain.Page_request.default_limit)
  ;;
end
