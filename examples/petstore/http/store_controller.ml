open! Base
open Typed_endpoint

module Make
    (B : Backend.S)
    (Pets : Pet_service.S with type 'a io = 'a B.io)
    (Orders : Order_service.S with type 'a io = 'a B.io and type database = Pets.database) =
struct
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

  let get_inventory =
    get / "store" / "inventory"
    |> documented
         ~operation_id:"getInventory"
         ~summary:"Returns pet inventories by status."
         ~description:"Returns a map of status names to quantities."
         ()
    |> accepts Request.empty
    |> returns
         (JSON.ok (module Dto.Inventory)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun context () ->
    let database = Common.Secured.dependency context in
    let%map result = Pets.inventory ~database in
    match result with
    | Ok inventory -> OK (Dto.Inventory.of_domain inventory)
    | Error error -> unavailable error
  ;;

  let place_order =
    post / "store" / "order"
    |> documented
         ~operation_id:"placeOrder"
         ~summary:"Place an order for a pet."
         ~description:"Place a new order in the store."
         ()
    |> accepts (Request.json (module Dto.Order))
    |> returns
         (JSON.ok (module Dto.Order)
          <|> JSON.bad_request (module Dto.Api_response)
          <|> JSON.client_errors [ `Unprocessable_entity ] (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun database order ->
    match Dto.Order.to_domain order with
    | Error message -> Io.return (Bad_request (Dto.Api_response.bad_request message))
    | Ok (id, attributes) ->
      let%map result = Orders.place ~database ?id attributes in
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
    get / "store" / "order" /: arg "orderId" (module Http_parameter.Order_id)
    |> documented
         ~operation_id:"getOrderById"
         ~summary:"Find purchase order by ID."
         ~description:"Returns a stored purchase order."
         ()
    |> accepts Request.empty
    |> returns
         (JSON.ok (module Dto.Order)
          <|> JSON.not_found (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun id database () ->
    let%map result = Orders.find ~database id in
    match result with
    | Ok (Some order) -> OK (Dto.Order.of_domain order)
    | Ok None -> Not_found (Dto.Api_response.order_not_found id)
    | Error error -> unavailable error
  ;;

  let delete_order =
    delete / "store" / "order" /: arg "orderId" (module Http_parameter.Order_id)
    |> documented
         ~operation_id:"deleteOrder"
         ~summary:"Delete purchase order by identifier."
         ~description:"Deletes a stored purchase order."
         ()
    |> accepts Request.empty
    |> returns
         (ok (Response.empty ~description:"Order deleted" ())
          <|> JSON.not_found (module Dto.Api_response)
          <|> JSON.server_errors [ `Service_unavailable ] (module Dto.Api_response))
    ==> fun id database () ->
    let%map result = Orders.delete ~database id in
    match result with
    | Ok () -> OK ()
    | Error (`Not_found id) -> Not_found (Dto.Api_response.order_not_found id)
    | Error (`Persistence error) -> unavailable error
  ;;

  let groups ~auth ~database =
    [ Group.make_with_context
        ~context:(Common.api_key ~auth database)
        ~decode_error:Common.decode_errors
        ~tags:[ "store" ]
        ~description:"Access to Petstore inventory"
        [ get_inventory ]
    ; Group.make_with_context
        ~context:(Common.public database)
        ~decode_error:Common.decode_errors
        ~tags:[ "store" ]
        ~description:"Access to Petstore orders"
        [ place_order; get_order; delete_order ]
    ]
  ;;
end
