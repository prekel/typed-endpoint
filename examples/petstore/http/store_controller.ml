open! Base
open Typed_endpoint

module Make
    (B : Backend.S)
    (Pets : Pet_service.S with type 'a io = 'a B.io)
    (Orders : Order_service.S with type 'a io = 'a B.io) =
struct
  module Common = Controller_context.Make (B)
  module Endpoint = Common.Endpoint
  module Io = B.Io
  open Io.Let_syntax
  open Endpoint
  open Dsl

  type t =
    { pets : Pets.t
    ; orders : Orders.t
    }

  let create ~pets ~orders = { pets; orders }

  let unavailable error =
    Code_5xx (`Service_unavailable, Dto.Api_response.persistence_error error)
  ;;

  let get_inventory =
    make_in_group
      ~meth:B.get
      ~operation_id:"getInventory"
      ~summary:"Returns pet inventories by status."
      ~description:"Returns a map of status names to quantities."
      ~path:(s "store" / s "inventory" /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Inventory)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun controller () ->
    let%map result = Pets.inventory controller.pets in
    match result with
    | Ok inventory -> OK (Dto.Inventory.of_domain inventory)
    | Error error -> unavailable error
  ;;

  let place_order =
    make_in_group
      ~meth:B.post
      ~operation_id:"placeOrder"
      ~summary:"Place an order for a pet."
      ~description:"Place a new order in the store."
      ~path:(s "store" / s "order" /? nil)
      ~request:(Request.json (module Dto.Order))
      ~responses:
        (JSON.ok (module Dto.Order)
         |+ JSON.bad_request (module Dto.Api_response)
         |+ code4xx [ `Unprocessable_entity ] (Response.json (module Dto.Api_response))
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun controller order ->
    match Dto.Order.to_domain order with
    | Error message -> Io.return (Bad_request (Dto.Api_response.bad_request message))
    | Ok (id, attributes) ->
      let%map result = Orders.place controller.orders ?id attributes in
      (match result with
       | Ok order -> OK (Dto.Order.of_domain order)
       | Error (`Pet_not_found _) ->
         Bad_request (Dto.Api_response.bad_request "ordered pet does not exist")
       | Error (`Already_exists id) ->
         Code_4xx
           ( `Unprocessable_entity
           , Dto.Api_response.bad_request ("order " ^ Int.to_string id ^ " already exists")
           )
       | Error (`Persistence error) -> unavailable error)
  ;;

  let get_order =
    make_in_group
      ~meth:B.get
      ~operation_id:"getOrderById"
      ~summary:"Find purchase order by ID."
      ~description:"Returns a stored purchase order."
      ~path:
        (s "store" / s "order" / param "orderId" (module Http_parameter.Order_id) /? nil)
      ~request:Request.empty
      ~responses:
        (JSON.ok (module Dto.Order)
         |+ JSON.not_found (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun id controller () ->
    let%map result = Orders.find controller.orders id in
    match result with
    | Ok (Some order) -> OK (Dto.Order.of_domain order)
    | Ok None -> Not_found (Dto.Api_response.order_not_found id)
    | Error error -> unavailable error
  ;;

  let delete_order =
    make_in_group
      ~meth:B.delete
      ~operation_id:"deleteOrder"
      ~summary:"Delete purchase order by identifier."
      ~description:"Deletes a stored purchase order."
      ~path:
        (s "store" / s "order" / param "orderId" (module Http_parameter.Order_id) /? nil)
      ~request:Request.empty
      ~responses:
        (ok (Response.empty ~description:"Order deleted" ())
         |+ JSON.not_found (module Dto.Api_response)
         |+ code5xx [ `Service_unavailable ] (Response.json (module Dto.Api_response)))
    @@ fun id controller () ->
    let%map result = Orders.delete controller.orders id in
    match result with
    | Ok () -> OK ()
    | Error (`Not_found id) -> Not_found (Dto.Api_response.order_not_found id)
    | Error (`Persistence error) -> unavailable error
  ;;

  let groups ~auth controller =
    [ Group.make_with_context
        ~context:(Common.api_key ~auth controller)
        ~decode_error:Common.decode_errors
        ~tags:[ "store" ]
        ~description:"Access to Petstore inventory"
        [ get_inventory ]
    ; Group.make_with_context
        ~context:(Common.public controller)
        ~decode_error:Common.decode_errors
        ~tags:[ "store" ]
        ~description:"Access to Petstore orders"
        [ place_order; get_order; delete_order ]
    ]
  ;;
end
