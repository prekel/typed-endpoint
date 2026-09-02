open! Base
open Typed_endpoint
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson

module Category = struct
  type t =
    { id : int option [@default None] [@jsonschema.option]
    ; name : string option [@default None] [@jsonschema.option]
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:t_jsonschema
      ~schema_name:"Category"
      ~description:"A pet category"
      ()
  ;;
end

module Tag = struct
  type t =
    { id : int option [@default None] [@jsonschema.option]
    ; name : string option [@default None] [@jsonschema.option]
    }
  [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~schema_name:"Tag" ~description:"A pet tag" ()
  ;;
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
    | "available" | "pending" | "sold" -> true
    | _ -> false
  ;;

  let derived_of_yojson = of_yojson

  let of_yojson json =
    derived_of_yojson json
    |> Result.bind ~f:(fun pet ->
      match pet.status with
      | None -> Ok pet
      | Some status when valid_status status -> Ok pet
      | Some _ -> Error "status must be available, pending, or sold")
  ;;

  let schema =
    let status_schema =
      `Assoc
        [ "type", `String "string"
        ; "enum", `List [ `String "available"; `String "pending"; `String "sold" ]
        ]
    in
    let replace key value fields =
      List.map fields ~f:(fun (candidate, current) ->
        if String.equal candidate key then
          candidate, value
        else
          candidate, current)
    in
    match t_jsonschema with
    | `Assoc fields ->
      let fields =
        List.map fields ~f:(fun (key, value) ->
          match key, value with
          | "properties", `Assoc properties ->
            key, `Assoc (replace "status" status_schema properties)
          | _ -> key, value)
      in
      `Assoc fields
    | schema -> schema
  ;;

  let metadata : t Metadata.t =
    Metadata.v ~schema ~schema_name:"Pet" ~description:"A pet in the store" ()
  ;;
end

module Pet_list = struct
  type t = Pet.t list [@@deriving to_yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Pets matching the query" ()
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
      ~schema:t_jsonschema
      ~schema_name:"ApiResponse"
      ~description:"An API error"
      ()
  ;;

  let of_decode_error error =
    let message =
      match error with
      | Decode_error.Invalid_parameter { name; error; _ } -> name ^ ": " ^ error
      | Missing_parameter { name; _ } -> "missing parameter: " ^ name
      | Invalid_json { error } -> "invalid JSON: " ^ error
      | Invalid_body { error } -> "invalid request body: " ^ error
      | Unsupported_media_type { actual; _ } ->
        "unsupported media type: " ^ Option.value actual ~default:"missing"
      | Body_too_large { max_bytes } ->
        "request body exceeds " ^ Int.to_string max_bytes ^ " bytes"
    in
    { code = 0; type_ = "decode_error"; message }
  ;;

  let not_found id =
    { code = 404
    ; type_ = "not_found"
    ; message = "pet " ^ Int.to_string id ^ " not found"
    }
  ;;
end
