open! Base
open Typed_endpoint
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson

let replace_schema_properties schema replacements =
  match schema with
  | `Assoc fields ->
    `Assoc
      (List.map fields ~f:(fun (key, value) ->
         match key, value with
         | "properties", `Assoc properties ->
           ( key
           , `Assoc
               (List.map properties ~f:(fun (name, schema) ->
                  ( name
                  , Option.value
                      (List.Assoc.find replacements ~equal:String.equal name)
                      ~default:schema ))) )
         | _ -> key, value))
  | schema -> schema
;;

module Status = struct
  type t = Domain.Status.t

  let of_string = function
    | "available" -> Ok Domain.Status.Available
    | "pending" -> Ok Domain.Status.Pending
    | "sold" -> Ok Domain.Status.Sold
    | _ -> Error "status must be available, pending, or sold"
  ;;

  let to_string = function
    | Domain.Status.Available -> "available"
    | Domain.Status.Pending -> "pending"
    | Domain.Status.Sold -> "sold"
  ;;

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (`Assoc
            [ "type", `String "string"
            ; "enum", `List [ `String "available"; `String "pending"; `String "sold" ]
            ])
      ~description:"Pet status"
      ()
  ;;
end

module Category = struct
  type t =
    { id : int option [@default None] [@jsonschema.option]
    ; name : string option [@default None] [@jsonschema.option]
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (replace_schema_properties
           t_jsonschema
           [ "id", `Assoc [ "type", `String "integer"; "format", `String "int64" ] ])
      ~schema_name:"Category"
      ~description:"A pet category"
      ()
  ;;

  let to_domain { id; name } = Domain.Category.{ id; name }
  let of_domain ({ id; name } : Domain.Category.t) = { id; name }
end

module Tag = struct
  type t =
    { id : int option [@default None] [@jsonschema.option]
    ; name : string option [@default None] [@jsonschema.option]
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (replace_schema_properties
           t_jsonschema
           [ "id", `Assoc [ "type", `String "integer"; "format", `String "int64" ] ])
      ~schema_name:"Tag"
      ~description:"A pet tag"
      ()
  ;;

  let to_domain { id; name } = Domain.Tag.{ id; name }
  let of_domain ({ id; name } : Domain.Tag.t) = { id; name }
end

module Pet = struct
  type t =
    { id : int option [@default None] [@jsonschema.option]
    ; name : string
    ; category : Category.t option [@default None] [@jsonschema.option]
    ; photo_urls : string list [@key "photoUrls"] [@jsonschema.key "photoUrls"]
    ; tags : Tag.t list option [@default None] [@jsonschema.option]
    ; status : string option [@default None] [@jsonschema.option]
    }
  [@@deriving yojson, jsonschema]

  let valid_status = function
    | status -> Result.is_ok (Status.of_string status)
  ;;

  let derived_of_yojson = of_yojson

  let of_yojson json =
    let open Result.Let_syntax in
    let%bind pet = derived_of_yojson json in
    match pet.status with
    | None -> Ok pet
    | Some status when valid_status status -> Ok pet
    | Some _ -> Error "status must be available, pending, or sold"
  ;;

  let schema =
    let id_schema =
      `Assoc [ "type", `String "integer"; "format", `String "int64"; "minimum", `Int 1 ]
    in
    let status_schema =
      `Assoc
        [ "type", `String "string"
        ; "enum", `List [ `String "available"; `String "pending"; `String "sold" ]
        ]
    in
    replace_schema_properties t_jsonschema [ "id", id_schema; "status", status_schema ]
  ;;

  let metadata : t Metadata.t =
    Metadata.v ~schema ~schema_name:"Pet" ~description:"A pet in the store" ()
  ;;

  let to_domain pet =
    let open Result.Let_syntax in
    match pet.id with
    | Some id when id < 1 -> Error "id must be a positive integer"
    | id ->
      let%map status =
        match pet.status with
        | None -> Ok None
        | Some status ->
          let%map status = Status.of_string status in
          Some status
      in
      ( id
      , Domain.Pet.
          { name = pet.name
          ; category = Option.map pet.category ~f:Category.to_domain
          ; photo_urls = pet.photo_urls
          ; tags = Option.map pet.tags ~f:(List.map ~f:Tag.to_domain)
          ; status
          } )
  ;;

  let of_domain ({ id; attributes } : Domain.Pet.t) =
    { id = Some id
    ; name = attributes.name
    ; category = Option.map attributes.category ~f:Category.of_domain
    ; photo_urls = attributes.photo_urls
    ; tags = Option.map attributes.tags ~f:(List.map ~f:Tag.of_domain)
    ; status = Option.map attributes.status ~f:Status.to_string
    }
  ;;
end

module Tags = struct
  type t = string list

  let of_string value =
    let tags =
      String.split value ~on:','
      |> List.map ~f:String.strip
      |> List.filter ~f:(Fn.non String.is_empty)
    in
    if List.is_empty tags then
      Error "at least one tag is required"
    else
      Ok tags
  ;;

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (`Assoc
            [ "type", `String "array"
            ; "items", `Assoc [ "type", `String "string" ]
            ; "minItems", `Int 1
            ])
      ~description:"Comma-separated tags to filter by"
      ()
  ;;
end

module Pet_list = struct
  type t = Pet.t list [@@deriving to_yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Pets matching the filter" ()
  ;;

  let of_domain pets = List.map pets ~f:Pet.of_domain
end

module Pagination = struct
  type t =
    { page : int
    ; limit : int
    ; total : int
    ; total_pages : int [@key "totalPages"] [@jsonschema.key "totalPages"]
    }
  [@@deriving to_yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:t_jsonschema
      ~schema_name:"Pagination"
      ~description:"Pagination metadata"
      ()
  ;;

  let of_domain ({ page; limit; total; total_pages; _ } : _ Domain.Page.t) =
    { page; limit; total; total_pages }
  ;;
end

module Pet_page = struct
  type t =
    { items : Pet.t list
    ; pagination : Pagination.t
    }
  [@@deriving to_yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:t_jsonschema
      ~schema_name:"PetPage"
      ~description:"One page of pets matching the query"
      ()
  ;;

  let of_domain (page : Domain.Pet.t Domain.Page.t) =
    { items = List.map page.items ~f:Pet.of_domain
    ; pagination = Pagination.of_domain page
    }
  ;;
end

module Inventory = struct
  type t = (string * int) list

  let to_yojson inventory =
    `Assoc (List.map inventory ~f:(fun (status, count) -> status, `Int count))
  ;;

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (`Assoc
            [ "type", `String "object"
            ; ( "additionalProperties"
              , `Assoc [ "type", `String "integer"; "format", `String "int32" ] )
            ])
      ~description:"Pet quantities keyed by lifecycle status"
      ()
  ;;

  let of_domain inventory =
    List.map inventory ~f:(fun (status, count) -> Status.to_string status, count)
  ;;
end

module Order_status = struct
  let of_string = function
    | "placed" -> Ok Domain.Order.Status.Placed
    | "approved" -> Ok Domain.Order.Status.Approved
    | "delivered" -> Ok Domain.Order.Status.Delivered
    | _ -> Error "order status must be placed, approved, or delivered"
  ;;

  let to_string = function
    | Domain.Order.Status.Placed -> "placed"
    | Domain.Order.Status.Approved -> "approved"
    | Domain.Order.Status.Delivered -> "delivered"
  ;;
end

module Order = struct
  type t =
    { id : int option [@default None] [@jsonschema.option]
    ; pet_id : int option
          [@key "petId"] [@jsonschema.key "petId"] [@default None] [@jsonschema.option]
    ; quantity : int option [@default None] [@jsonschema.option]
    ; ship_date : string option
          [@key "shipDate"]
          [@jsonschema.key "shipDate"]
          [@default None]
          [@jsonschema.option]
    ; status : string option [@default None] [@jsonschema.option]
    ; complete : bool option [@default None] [@jsonschema.option]
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (replace_schema_properties
           t_jsonschema
           [ ( "id"
             , `Assoc
                 [ "type", `String "integer"
                 ; "format", `String "int64"
                 ; "minimum", `Int 1
                 ] )
           ; ( "petId"
             , `Assoc
                 [ "type", `String "integer"
                 ; "format", `String "int64"
                 ; "minimum", `Int 1
                 ] )
           ; ( "quantity"
             , `Assoc
                 [ "type", `String "integer"
                 ; "format", `String "int32"
                 ; "minimum", `Int 1
                 ] )
           ; ( "shipDate"
             , `Assoc [ "type", `String "string"; "format", `String "date-time" ] )
           ; ( "status"
             , `Assoc
                 [ "type", `String "string"
                 ; ( "enum"
                   , `List [ `String "placed"; `String "approved"; `String "delivered" ] )
                 ] )
           ])
      ~schema_name:"Order"
      ~description:"A store order for a pet"
      ()
  ;;

  let positive field = function
    | None -> Ok None
    | Some value when value > 0 -> Ok (Some value)
    | Some _ -> Error (field ^ " must be a positive integer")
  ;;

  let to_domain order =
    let open Result.Let_syntax in
    let%bind id = positive "id" order.id in
    let%bind pet_id = positive "petId" order.pet_id in
    let%bind quantity = positive "quantity" order.quantity in
    let%map status =
      match order.status with
      | None -> Ok None
      | Some status ->
        let%map status = Order_status.of_string status in
        Some status
    in
    ( id
    , Domain.Order.
        { pet_id
        ; quantity
        ; ship_date = order.ship_date
        ; status
        ; complete = order.complete
        } )
  ;;

  let of_domain ({ id; attributes } : Domain.Order.t) =
    { id = Some id
    ; pet_id = attributes.pet_id
    ; quantity = attributes.quantity
    ; ship_date = attributes.ship_date
    ; status = Option.map attributes.status ~f:Order_status.to_string
    ; complete = attributes.complete
    }
  ;;
end

module User = struct
  type t =
    { id : int option [@default None] [@jsonschema.option]
    ; username : string option [@default None] [@jsonschema.option]
    ; first_name : string option
          [@key "firstName"]
          [@jsonschema.key "firstName"]
          [@default None]
          [@jsonschema.option]
    ; last_name : string option
          [@key "lastName"]
          [@jsonschema.key "lastName"]
          [@default None]
          [@jsonschema.option]
    ; email : string option [@default None] [@jsonschema.option]
    ; password : string option [@default None] [@jsonschema.option]
    ; phone : string option [@default None] [@jsonschema.option]
    ; user_status : int option
          [@key "userStatus"]
          [@jsonschema.key "userStatus"]
          [@default None]
          [@jsonschema.option]
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (replace_schema_properties
           t_jsonschema
           [ "id", `Assoc [ "type", `String "integer"; "format", `String "int64" ]
           ; "userStatus", `Assoc [ "type", `String "integer"; "format", `String "int32" ]
           ])
      ~schema_name:"User"
      ~description:"A Petstore user"
      ()
  ;;

  let to_domain ?username:user_identity user =
    match Option.first_some user_identity user.username with
    | None -> Error "username is required"
    | Some username when String.is_empty (String.strip username) ->
      Error "username must not be empty"
    | Some username ->
      Ok
        Domain.User.
          { username
          ; attributes =
              { id = user.id
              ; first_name = user.first_name
              ; last_name = user.last_name
              ; email = user.email
              ; password = user.password
              ; phone = user.phone
              ; user_status = user.user_status
              }
          }
  ;;

  let of_domain ({ username; attributes } : Domain.User.t) =
    { id = attributes.id
    ; username = Some username
    ; first_name = attributes.first_name
    ; last_name = attributes.last_name
    ; email = attributes.email
    ; password = attributes.password
    ; phone = attributes.phone
    ; user_status = attributes.user_status
    }
  ;;
end

module User_list = struct
  type t = User.t list [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Users to create atomically" ()
  ;;

  let to_domain users = users |> List.map ~f:User.to_domain |> Result.all
end

module Login_token = struct
  type t = string [@@deriving to_yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Authenticated session token" ()
  ;;
end

module Api_response = struct
  type t =
    { code : int
    ; type_ : string [@key "type"] [@jsonschema.key "type"]
    ; message : string
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:
        (replace_schema_properties
           t_jsonschema
           [ "code", `Assoc [ "type", `String "integer"; "format", `String "int32" ] ])
      ~schema_name:"ApiResponse"
      ~description:"An API error"
      ()
  ;;

  let of_decode_error error =
    let code, message =
      match error with
      | Decode_error.Invalid_parameter { name; error; _ } -> 400, name ^ ": " ^ error
      | Missing_parameter { name; _ } -> 400, "missing parameter: " ^ name
      | Invalid_json { error } -> 400, "invalid JSON: " ^ error
      | Invalid_body { error } -> 400, "invalid request body: " ^ error
      | Unsupported_media_type { actual; _ } ->
        415, "unsupported media type: " ^ Option.value actual ~default:"missing"
      | Body_too_large { max_bytes } ->
        413, "request body exceeds " ^ Int.to_string max_bytes ^ " bytes"
    in
    { code; type_ = "decode_error"; message }
  ;;

  let not_found id =
    { code = 404
    ; type_ = "not_found"
    ; message = "pet " ^ Int.to_string id ^ " not found"
    }
  ;;

  let conflict id =
    { code = 409
    ; type_ = "conflict"
    ; message = "pet " ^ Int.to_string id ^ " already exists"
    }
  ;;

  let bad_request message = { code = 400; type_ = "bad_request"; message }

  let order_not_found id =
    { code = 404
    ; type_ = "not_found"
    ; message = "order " ^ Int.to_string id ^ " not found"
    }
  ;;

  let user_not_found username =
    { code = 404; type_ = "not_found"; message = "user " ^ username ^ " not found" }
  ;;

  let user_conflict username =
    { code = 409; type_ = "conflict"; message = "user " ^ username ^ " already exists" }
  ;;

  let upload_success ~id ~bytes ~metadata =
    let metadata =
      Option.value_map metadata ~default:"" ~f:(fun value -> ", metadata: " ^ value)
    in
    { code = 200
    ; type_ = "upload"
    ; message =
        "uploaded "
        ^ Int.to_string bytes
        ^ " bytes for pet "
        ^ Int.to_string id
        ^ metadata
    }
  ;;
end
