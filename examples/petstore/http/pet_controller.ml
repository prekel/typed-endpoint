open! Base
open Typed_endpoint

module Make (B : Backend.S) (Pets : Pet_service.S with type 'a io = 'a B.io) = struct
  module Common = Controller_context.Make (B)
  module Endpoint = Common.Endpoint
  module Io = B.Io
  open Io.Let_syntax
  open Endpoint
  open Dsl
  open Staged

  let unavailable error =
    Code_5xx (`Service_unavailable, Dto.Api_response.persistence_error error)
  ;;

  let add_pet =
    post / "pet"
    |> documented
         ~operation_id:"addPet"
         ~summary:"Add a new pet to the store."
         ~description:"Add a new pet to the store."
         ()
    |> accepts (Request.json (module Dto.Pet))
    |> returns
         (JSON.ok (module Dto.Pet)
          <|> JSON.client_errors
                [ `Bad_request; `Conflict; `Unprocessable_entity ]
                (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun context pet ->
    let database = Common.Secured.dependency context in
    match Dto.Pet.to_domain pet with
    | Error message ->
      Io.return (Code_4xx (`Bad_request, Dto.Api_response.bad_request message))
    | Ok (id, attributes) ->
      let%map result = Pets.add ~database ?id attributes in
      (match result with
       | Ok pet -> OK (Dto.Pet.of_domain pet)
       | Error (`Already_exists id) -> Code_4xx (`Conflict, Dto.Api_response.conflict id)
       | Error (`Persistence error) -> unavailable error)
  ;;

  let update_pet =
    put / "pet"
    |> documented
         ~operation_id:"updatePet"
         ~summary:"Update an existing pet."
         ~description:"Update an existing pet by ID."
         ()
    |> accepts (Request.json (module Dto.Pet))
    |> returns
         (JSON.ok (module Dto.Pet)
          <|> JSON.bad_request (module Dto.Api_response)
          <|> JSON.not_found (module Dto.Api_response)
          <|> JSON.client_errors [ `Unprocessable_entity ] (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun context pet ->
    let database = Common.Secured.dependency context in
    match Dto.Pet.to_domain pet with
    | Error message -> Io.return (Bad_request (Dto.Api_response.bad_request message))
    | Ok (None, _) ->
      Io.return (Bad_request (Dto.Api_response.bad_request "id is required"))
    | Ok (Some id, attributes) ->
      let%map result = Pets.update ~database ~id attributes in
      (match result with
       | Ok pet -> OK (Dto.Pet.of_domain pet)
       | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id)
       | Error (`Persistence error) -> unavailable error)
  ;;

  let find_by_status =
    get / "pet" / "findByStatus" /! arg "status" (module Dto.Status)
    |> documented
         ~operation_id:"findPetsByStatus"
         ~summary:"Finds Pets by status."
         ~description:"Returns all pets having the requested official status."
         ()
    |> accepts Request.empty
    |> returns
         (JSON.ok (module Dto.Pet_list)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun status context () ->
    let database = Common.Secured.dependency context in
    let%map result = Pets.list_by_status ~database ~status in
    match result with
    | Ok pets -> OK (Dto.Pet_list.of_domain pets)
    | Error error -> unavailable error
  ;;

  let find_by_tags =
    get / "pet" / "findByTags" /! arg "tags" (module Dto.Tags)
    |> documented
         ~operation_id:"findPetsByTags"
         ~summary:"Finds Pets by tags."
         ~description:"Returns pets carrying at least one comma-separated tag."
         ()
    |> accepts Request.empty
    |> returns
         (JSON.ok (module Dto.Pet_list)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun tags context () ->
    let database = Common.Secured.dependency context in
    let%map result = Pets.list_by_tags ~database ~tags in
    match result with
    | Ok pets -> OK (Dto.Pet_list.of_domain pets)
    | Error error -> unavailable error
  ;;

  let search_pets =
    get
    / "pet"
    / "search"
    /! arg "status" (module Dto.Status)
    /? arg "page" (module Http_parameter.Page)
    /? arg "limit" (module Http_parameter.Limit)
    |> documented
         ~operation_id:"searchPets"
         ~summary:"Search pets with pagination."
         ~description:
           "Typed-endpoint extension retaining bounded pagination outside the official operations."
         ()
    |> accepts Request.empty
    |> returns
         (JSON.ok (module Dto.Pet_page)
          <|> JSON.bad_request (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun status page limit context () ->
    let database = Common.Secured.dependency context in
    let page = Option.value page ~default:Domain.Page_request.default_page in
    let limit = Option.value limit ~default:Domain.Page_request.default_limit in
    match Domain.Page_request.create ~page ~limit with
    | Error message -> Io.return (Bad_request (Dto.Api_response.bad_request message))
    | Ok pagination ->
      let%map result = Pets.find_by_status ~database ~status ~pagination in
      (match result with
       | Ok page -> OK (Dto.Pet_page.of_domain page)
       | Error error -> unavailable error)
  ;;

  let get_pet =
    get / "pet" /: arg "petId" (module Http_parameter.Pet_id)
    |> documented
         ~operation_id:"getPetById"
         ~summary:"Find pet by ID."
         ~description:"Returns a single pet."
         ()
    |> accepts Request.empty
    |> returns
         (JSON.ok (module Dto.Pet)
          <|> JSON.not_found (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun id context () ->
    let database = Common.Secured.dependency context in
    let%map result = Pets.find ~database id in
    match result with
    | Ok (Some pet) -> OK (Dto.Pet.of_domain pet)
    | Ok None -> Not_found (Dto.Api_response.not_found id)
    | Error error -> unavailable error
  ;;

  let update_pet_with_form =
    post
    / "pet"
    /: arg "petId" (module Http_parameter.Pet_id)
    /? arg "name" (module Http_parameter.Pet_name)
    /? arg "status" (module Dto.Status)
    |> documented
         ~operation_id:"updatePetWithForm"
         ~summary:"Updates a pet in the store with form data."
         ~description:"Updates the pet name and/or status from query form fields."
         ()
    |> accepts Request.empty
    |> returns
         (JSON.ok (module Dto.Pet)
          <|> JSON.bad_request (module Dto.Api_response)
          <|> JSON.not_found (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun id name status context () ->
    let database = Common.Secured.dependency context in
    let%map result = Pets.patch ~database ~id ?name ?status () in
    match result with
    | Ok pet -> OK (Dto.Pet.of_domain pet)
    | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id)
    | Error (`Persistence error) -> unavailable error
  ;;

  let delete_pet =
    delete / "pet" /: arg "petId" (module Http_parameter.Pet_id)
    |> documented
         ~operation_id:"deletePet"
         ~summary:"Deletes a pet."
         ~description:"Delete a pet."
         ()
    |> accepts Request.empty
    |> returns
         (ok (Response.empty ~description:"Pet deleted" ())
          <|> JSON.not_found (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun id context () ->
    let database = Common.Secured.dependency context in
    let%map result = Pets.delete ~database id in
    match result with
    | Ok () -> OK ()
    | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id)
    | Error (`Persistence error) -> unavailable error
  ;;

  let upload_image =
    post
    / "pet"
    /: arg "petId" (module Http_parameter.Pet_id)
    / "uploadImage"
    /? arg "additionalMetadata" (Parameter.string ~description:"Additional metadata" ())
    |> documented
         ~operation_id:"uploadFile"
         ~summary:"Uploads an image."
         ~description:"Upload an opaque image of the pet."
         ()
    |> accepts (Request.binary ~description:"Image bytes" ())
    |> returns
         (JSON.ok (module Dto.Api_response)
          <|> JSON.bad_request (module Dto.Api_response)
          <|> JSON.not_found (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun id metadata context bytes ->
    let database = Common.Secured.dependency context in
    let%map result = Pets.upload_image ~database ~id ~metadata ~bytes in
    match result with
    | Ok bytes -> OK (Dto.Api_response.upload_success ~id ~bytes ~metadata)
    | Error `Empty_file -> Bad_request (Dto.Api_response.bad_request "no file uploaded")
    | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id)
    | Error (`Persistence error) -> unavailable error
  ;;

  let groups ~auth ~database =
    let group ~context ~description routes =
      Group.make_with_context
        ~context
        ~decode_error:Common.decode_errors
        ~tags:[ "pet" ]
        ~description
        routes
    in
    [ group
        ~context:(Common.pet_oauth ~auth database)
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
        ~context:(Common.pet_lookup ~auth database)
        ~description:"Pet lookup accepting the official alternative credentials"
        [ get_pet ]
    ]
  ;;
end
