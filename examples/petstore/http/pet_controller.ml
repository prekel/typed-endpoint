open! Base
open Typed_endpoint

module Make (B : Backend.S) (Pets : Pet_service.S with type 'a io = 'a B.io) = struct
  module Common = Controller_context.Make (B)
  module Endpoint = Common.Endpoint
  module Io = B.Io
  open Io.Let_syntax
  open Endpoint
  open Dsl

  type t = { pets : Pets.t }

  let create ~pets = { pets }

  let unavailable error =
    Code_5xx (`Service_unavailable, Dto.Api_response.persistence_error error)
  ;;

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
              (Response.json (module Dto.Api_response))
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun controller pet ->
    match Dto.Pet.to_domain pet with
    | Error message ->
      Io.return (Code_4xx (`Bad_request, Dto.Api_response.bad_request message))
    | Ok (id, attributes) ->
      let%map result = Pets.add controller.pets ?id attributes in
      (match result with
       | Ok pet -> OK (Dto.Pet.of_domain pet)
       | Error (`Already_exists id) -> Code_4xx (`Conflict, Dto.Api_response.conflict id)
       | Error (`Persistence error) -> unavailable error)
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
         |+ code4xx [ `Unprocessable_entity ] (Response.json (module Dto.Api_response))
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun controller pet ->
    match Dto.Pet.to_domain pet with
    | Error message -> Io.return (Bad_request (Dto.Api_response.bad_request message))
    | Ok (None, _) ->
      Io.return (Bad_request (Dto.Api_response.bad_request "id is required"))
    | Ok (Some id, attributes) ->
      let%map result = Pets.update controller.pets ~id attributes in
      (match result with
       | Ok pet -> OK (Dto.Pet.of_domain pet)
       | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id)
       | Error (`Persistence error) -> unavailable error)
  ;;

  let find_by_status =
    make_in_group
      ~meth:B.get
      ~operation_id:"findPetsByStatus"
      ~summary:"Finds Pets by status."
      ~description:"Returns all pets having the requested official status."
      ~path:(s "pet" / s "findByStatus" / query_req "status" (module Dto.Status) /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Pet_list)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun status controller () ->
    let%map result = Pets.list_by_status controller.pets ~status in
    match result with
    | Ok pets -> OK (Dto.Pet_list.of_domain pets)
    | Error error -> unavailable error
  ;;

  let find_by_tags =
    make_in_group
      ~meth:B.get
      ~operation_id:"findPetsByTags"
      ~summary:"Finds Pets by tags."
      ~description:"Returns pets carrying at least one comma-separated tag."
      ~path:(s "pet" / s "findByTags" / query_req "tags" (module Dto.Tags) /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Pet_list)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun tags controller () ->
    let%map result = Pets.list_by_tags controller.pets ~tags in
    match result with
    | Ok pets -> OK (Dto.Pet_list.of_domain pets)
    | Error error -> unavailable error
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
         / query "page" (module Http_parameter.Page)
         / query "limit" (module Http_parameter.Limit)
         /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Pet_page)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun status page limit controller () ->
    let page = Option.value page ~default:Domain.Page_request.default_page in
    let limit = Option.value limit ~default:Domain.Page_request.default_limit in
    match Domain.Page_request.create ~page ~limit with
    | Error message -> Io.return (Bad_request (Dto.Api_response.bad_request message))
    | Ok pagination ->
      let%map result = Pets.find_by_status controller.pets ~status ~pagination in
      (match result with
       | Ok page -> OK (Dto.Pet_page.of_domain page)
       | Error error -> unavailable error)
  ;;

  let get_pet =
    make_in_group
      ~meth:B.get
      ~operation_id:"getPetById"
      ~summary:"Find pet by ID."
      ~description:"Returns a single pet."
      ~path:(s "pet" / param "petId" (module Http_parameter.Pet_id) /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Pet)
         |+ JSON.not_found (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun id controller () ->
    let%map result = Pets.find controller.pets id in
    match result with
    | Ok (Some pet) -> OK (Dto.Pet.of_domain pet)
    | Ok None -> Not_found (Dto.Api_response.not_found id)
    | Error error -> unavailable error
  ;;

  let update_pet_with_form =
    make_in_group
      ~meth:B.post
      ~operation_id:"updatePetWithForm"
      ~summary:"Updates a pet in the store with form data."
      ~description:"Updates the pet name and/or status from query form fields."
      ~path:
        (s "pet"
         / param "petId" (module Http_parameter.Pet_id)
         / query "name" (module Http_parameter.Pet_name)
         / query "status" (module Dto.Status)
         /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Pet)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ JSON.not_found (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun id name status controller () ->
    let%map result = Pets.patch controller.pets ~id ?name ?status () in
    match result with
    | Ok pet -> OK (Dto.Pet.of_domain pet)
    | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id)
    | Error (`Persistence error) -> unavailable error
  ;;

  let delete_pet =
    make_in_group
      ~meth:B.delete
      ~operation_id:"deletePet"
      ~summary:"Deletes a pet."
      ~description:"Delete a pet."
      ~path:(s "pet" / param "petId" (module Http_parameter.Pet_id) /? nil)
      ~request:Request.empty
      ~responses:
        (ok (Response.empty ~description:"Pet deleted" ())
         |+ JSON.not_found (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun id controller () ->
    let%map result = Pets.delete controller.pets id in
    match result with
    | Ok () -> OK ()
    | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id)
    | Error (`Persistence error) -> unavailable error
  ;;

  let upload_image =
    make_in_group
      ~meth:B.post
      ~operation_id:"uploadFile"
      ~summary:"Uploads an image."
      ~description:"Upload an opaque image of the pet."
      ~path:
        (s "pet"
         / param "petId" (module Http_parameter.Pet_id)
         / s "uploadImage"
         / query
             "additionalMetadata"
             (Parameter.string ~description:"Additional metadata" ())
         /? nil)
      ~request:(Request.binary ~description:"Image bytes" ())
      ~responses:
        (JSON.ok (module Dto.Api_response)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ JSON.not_found (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun id metadata controller bytes ->
    let%map result = Pets.upload_image controller.pets ~id ~metadata ~bytes in
    match result with
    | Ok bytes -> OK (Dto.Api_response.upload_success ~id ~bytes ~metadata)
    | Error `Empty_file -> Bad_request (Dto.Api_response.bad_request "no file uploaded")
    | Error (`Not_found id) -> Not_found (Dto.Api_response.not_found id)
    | Error (`Persistence error) -> unavailable error
  ;;

  let groups ~auth controller =
    let group ~context ~description routes =
      Group.make_with_context
        ~context
        ~decode_error:Common.decode_errors
        ~tags:[ "pet" ]
        ~description
        routes
    in
    [ group
        ~context:(Common.pet_oauth ~auth controller)
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
        ~context:(Common.pet_lookup ~auth controller)
        ~description:"Pet lookup accepting the official alternative credentials"
        [ get_pet ]
    ]
  ;;
end
