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

  let unavailable response_case error =
    respond response_case (Dto.Api_response.persistence_error error)
  ;;

  let add_pet =
    let ok = Response.case `OK (Response.json (module Dto.Pet)) in
    let bad_request =
      Response.case `Bad_request (Response.json (module Dto.Api_response))
    in
    let conflict = Response.case `Conflict (Response.json (module Dto.Api_response)) in
    let unprocessable_entity =
      Response.case `Unprocessable_entity (Response.json (module Dto.Api_response))
    in
    let service_unavailable =
      Response.case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    post / "pet"
    |> documented
         ~operation_id:"addPet"
         ~summary:"Add a new pet to the store."
         ~description:"Add a new pet to the store."
    |> accepts (Request.json (module Dto.Pet))
    |> returns
         (ok <|> bad_request <|> conflict <|> unprocessable_entity <|> service_unavailable)
    ==> fun context pet ->
    let database = Common.Secured.dependency context in
    match Dto.Pet.to_domain pet with
    | Error message -> respond bad_request (Dto.Api_response.bad_request message)
    | Ok (id, attributes) ->
      let%bind result = Pets.add ~database ?id attributes in
      (match result with
       | Ok pet -> respond ok (Dto.Pet.of_domain pet)
       | Error (`Already_exists id) -> respond conflict (Dto.Api_response.conflict id)
       | Error (`Persistence error) -> unavailable service_unavailable error)
  ;;

  let update_pet =
    let ok = Response.case `OK (Response.json (module Dto.Pet)) in
    let bad_request =
      Response.case `Bad_request (Response.json (module Dto.Api_response))
    in
    let not_found = Response.case `Not_found (Response.json (module Dto.Api_response)) in
    let unprocessable_entity =
      Response.case `Unprocessable_entity (Response.json (module Dto.Api_response))
    in
    let service_unavailable =
      Response.case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    put / "pet"
    |> documented
         ~operation_id:"updatePet"
         ~summary:"Update an existing pet."
         ~description:"Update an existing pet by ID."
    |> accepts (Request.json (module Dto.Pet))
    |> returns
         (ok
          <|> bad_request
          <|> not_found
          <|> unprocessable_entity
          <|> service_unavailable)
    ==> fun context pet ->
    let database = Common.Secured.dependency context in
    match Dto.Pet.to_domain pet with
    | Error message -> respond bad_request (Dto.Api_response.bad_request message)
    | Ok (None, _) -> respond bad_request (Dto.Api_response.bad_request "id is required")
    | Ok (Some id, attributes) ->
      let%bind result = Pets.update ~database ~id attributes in
      (match result with
       | Ok pet -> respond ok (Dto.Pet.of_domain pet)
       | Error (`Not_found id) -> respond not_found (Dto.Api_response.not_found id)
       | Error (`Persistence error) -> unavailable service_unavailable error)
  ;;

  let find_by_status =
    let ok = Response.case `OK (Response.json (module Dto.Pet_list)) in
    let service_unavailable =
      Response.case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    get / "pet" / "findByStatus" /! arg "status" (module Dto.Status)
    |> documented
         ~operation_id:"findPetsByStatus"
         ~summary:"Finds Pets by status."
         ~description:"Returns all pets having the requested official status."
    |> accepts Request.empty
    |> returns (ok <|> service_unavailable)
    ==> fun status context () ->
    let database = Common.Secured.dependency context in
    let%bind result = Pets.list_by_status ~database ~status in
    match result with
    | Ok pets -> respond ok (Dto.Pet_list.of_domain pets)
    | Error error -> unavailable service_unavailable error
  ;;

  let find_by_tags =
    let ok = Response.case `OK (Response.json (module Dto.Pet_list)) in
    let service_unavailable =
      Response.case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    get / "pet" / "findByTags" /! arg "tags" (module Dto.Tags)
    |> documented
         ~operation_id:"findPetsByTags"
         ~summary:"Finds Pets by tags."
         ~description:"Returns pets carrying at least one comma-separated tag."
    |> accepts Request.empty
    |> returns (ok <|> service_unavailable)
    ==> fun tags context () ->
    let database = Common.Secured.dependency context in
    let%bind result = Pets.list_by_tags ~database ~tags in
    match result with
    | Ok pets -> respond ok (Dto.Pet_list.of_domain pets)
    | Error error -> unavailable service_unavailable error
  ;;

  let search_pets =
    let ok = Response.case `OK (Response.json (module Dto.Pet_page)) in
    let bad_request =
      Response.case `Bad_request (Response.json (module Dto.Api_response))
    in
    let service_unavailable =
      Response.case `Service_unavailable (Response.json (module Dto.Api_response))
    in
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
    |> accepts Request.empty
    |> returns (ok <|> bad_request <|> service_unavailable)
    ==> fun status page limit context () ->
    let database = Common.Secured.dependency context in
    let page = Option.value page ~default:Domain.Page_request.default_page in
    let limit = Option.value limit ~default:Domain.Page_request.default_limit in
    match Domain.Page_request.create ~page ~limit with
    | Error message -> respond bad_request (Dto.Api_response.bad_request message)
    | Ok pagination ->
      let%bind result = Pets.find_by_status ~database ~status ~pagination in
      (match result with
       | Ok page -> respond ok (Dto.Pet_page.of_domain page)
       | Error error -> unavailable service_unavailable error)
  ;;

  let get_pet =
    let ok = Response.case `OK (Response.json (module Dto.Pet)) in
    let not_found = Response.case `Not_found (Response.json (module Dto.Api_response)) in
    let service_unavailable =
      Response.case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    get / "pet" /: arg "petId" (module Http_parameter.Pet_id)
    |> documented
         ~operation_id:"getPetById"
         ~summary:"Find pet by ID."
         ~description:"Returns a single pet."
    |> accepts Request.empty
    |> returns (ok <|> not_found <|> service_unavailable)
    ==> fun id context () ->
    let database = Common.Secured.dependency context in
    let%bind result = Pets.find ~database id in
    match result with
    | Ok (Some pet) -> respond ok (Dto.Pet.of_domain pet)
    | Ok None -> respond not_found (Dto.Api_response.not_found id)
    | Error error -> unavailable service_unavailable error
  ;;

  let update_pet_with_form =
    let ok = Response.case `OK (Response.json (module Dto.Pet)) in
    let bad_request =
      Response.case `Bad_request (Response.json (module Dto.Api_response))
    in
    let not_found = Response.case `Not_found (Response.json (module Dto.Api_response)) in
    let service_unavailable =
      Response.case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    post
    / "pet"
    /: arg "petId" (module Http_parameter.Pet_id)
    /? arg "name" (module Http_parameter.Pet_name)
    /? arg "status" (module Dto.Status)
    |> documented
         ~operation_id:"updatePetWithForm"
         ~summary:"Updates a pet in the store with form data."
         ~description:"Updates the pet name and/or status from query form fields."
    |> accepts Request.empty
    |> returns (ok <|> bad_request <|> not_found <|> service_unavailable)
    ==> fun id name status context () ->
    let database = Common.Secured.dependency context in
    let%bind result = Pets.patch ~database ~id ?name ?status () in
    match result with
    | Ok pet -> respond ok (Dto.Pet.of_domain pet)
    | Error (`Not_found id) -> respond not_found (Dto.Api_response.not_found id)
    | Error (`Persistence error) -> unavailable service_unavailable error
  ;;

  let delete_pet =
    let ok = Response.case `OK (Response.empty ~description:"Pet deleted" ()) in
    let not_found = Response.case `Not_found (Response.json (module Dto.Api_response)) in
    let service_unavailable =
      Response.case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    delete / "pet" /: arg "petId" (module Http_parameter.Pet_id)
    |> documented
         ~operation_id:"deletePet"
         ~summary:"Deletes a pet."
         ~description:"Delete a pet."
    |> accepts Request.empty
    |> returns (ok <|> not_found <|> service_unavailable)
    ==> fun id context () ->
    let database = Common.Secured.dependency context in
    let%bind result = Pets.delete ~database id in
    match result with
    | Ok () -> respond ok ()
    | Error (`Not_found id) -> respond not_found (Dto.Api_response.not_found id)
    | Error (`Persistence error) -> unavailable service_unavailable error
  ;;

  let upload_image =
    let ok = Response.case `OK (Response.json (module Dto.Api_response)) in
    let bad_request =
      Response.case `Bad_request (Response.json (module Dto.Api_response))
    in
    let not_found = Response.case `Not_found (Response.json (module Dto.Api_response)) in
    let service_unavailable =
      Response.case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    post
    / "pet"
    /: arg "petId" (module Http_parameter.Pet_id)
    / "uploadImage"
    /? arg "additionalMetadata" (Parameter.string ~description:"Additional metadata" ())
    |> documented
         ~operation_id:"uploadFile"
         ~summary:"Uploads an image."
         ~description:"Upload an opaque image of the pet."
    |> accepts (Request.binary ~description:"Image bytes" ())
    |> returns (ok <|> bad_request <|> not_found <|> service_unavailable)
    ==> fun id metadata context bytes ->
    let database = Common.Secured.dependency context in
    let%bind result = Pets.upload_image ~database ~id ~metadata ~bytes in
    match result with
    | Ok bytes -> respond ok (Dto.Api_response.upload_success ~id ~bytes ~metadata)
    | Error `Empty_file ->
      respond bad_request (Dto.Api_response.bad_request "no file uploaded")
    | Error (`Not_found id) -> respond not_found (Dto.Api_response.not_found id)
    | Error (`Persistence error) -> unavailable service_unavailable error
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
