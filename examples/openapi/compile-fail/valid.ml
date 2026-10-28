open! Base
module S = Generated_api.Server.Make (Typed_endpoint_testing)
module O = Generated_api.Operations

let handlers : unit S.Pets.Handlers.t =
  { get_pet = (fun () _ -> O.Get_pet.Response.Status_400 { message = "missing" })
  ; search_pets = (fun () _ -> O.Search_pets.Response.Status_400 { message = "invalid" })
  ; create_pet = (fun () _ -> O.Create_pet.Response.Status_400 { message = "invalid" })
  }
;;
