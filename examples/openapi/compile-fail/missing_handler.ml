open! Base
module S = Generated_api.Server.Make (Typed_endpoint_testing)
module O = Generated_api.Operations

let handlers : unit S.Pets.Handlers.t =
  { get_pet = (fun () _ -> O.Get_pet.Response.Status_400 { message = "missing" }) }
;;
