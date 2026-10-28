open! Base

module Make (B : Typed_endpoint.Backend.S) : sig
  val get
    :  Domain.t list
    -> Generated_api.Operations.Get_pet.Request.t
    -> Generated_api.Operations.Get_pet.Response.t B.io

  val create
    :  Domain.t list
    -> Generated_api.Operations.Create_pet.Request.t
    -> Generated_api.Operations.Create_pet.Response.t B.io
end
