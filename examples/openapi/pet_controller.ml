open! Base
module O = Generated_api.Operations

module Make (B : Typed_endpoint.Backend.S) = struct
  let get pets (request : O.Get_pet.Request.t) =
    let result =
      match Pet_service.find ~pets request.path_pet_id with
      | Some pet -> O.Get_pet.Response.Status_200 (Pet_mapping.of_domain pet)
      | None -> O.Get_pet.Response.Status_400 { message = "Pet not found" }
    in
    B.Io.return result
  ;;

  let create _pets (request : O.Create_pet.Request.t) =
    B.Io.return
      (O.Create_pet.Response.Status_200
         (request.body |> Pet_mapping.to_domain |> Pet_mapping.of_domain))
  ;;
end
