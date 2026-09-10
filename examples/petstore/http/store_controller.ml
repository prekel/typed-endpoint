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

  let unavailable response_case error =
    respond response_case (Dto.Api_response.persistence_error error)
  ;;

  let get_inventory =
    let ok = case `OK (Response.json (module Dto.Inventory)) in
    let service_unavailable =
      case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    get / "store" / "inventory"
    |> documented
         ~operation_id:"getInventory"
         ~summary:"Returns pet inventories by status."
         ~description:"Returns a map of status names to quantities."
    |> accepts Request.empty
    |> returns (ok <|> service_unavailable)
    ==> fun context () ->
    let database = Common.Secured.dependency context in
    let%bind result = Pets.inventory ~database in
    match result with
    | Ok inventory -> respond ok (Dto.Inventory.of_domain inventory)
    | Error error -> unavailable service_unavailable error
  ;;

  let place_order =
    let ok = case `OK (Response.json (module Dto.Order)) in
    let bad_request = case `Bad_request (Response.json (module Dto.Api_response)) in
    let unprocessable_entity =
      case `Unprocessable_entity (Response.json (module Dto.Api_response))
    in
    let service_unavailable =
      case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    post / "store" / "order"
    |> documented
         ~operation_id:"placeOrder"
         ~summary:"Place an order for a pet."
         ~description:"Place a new order in the store."
    |> accepts (Request.json (module Dto.Order))
    |> returns (ok <|> bad_request <|> unprocessable_entity <|> service_unavailable)
    ==> fun database order ->
    match Dto.Order.to_domain order with
    | Error message -> respond bad_request (Dto.Api_response.bad_request message)
    | Ok (id, attributes) ->
      let%bind result = Orders.place ~database ?id attributes in
      (match result with
       | Ok order -> respond ok (Dto.Order.of_domain order)
       | Error (`Pet_not_found _) ->
         respond bad_request (Dto.Api_response.bad_request "ordered pet does not exist")
       | Error (`Already_exists id) ->
         respond
           unprocessable_entity
           (Dto.Api_response.bad_request
              ("order " ^ Int.to_string id ^ " already exists"))
       | Error (`Persistence error) -> unavailable service_unavailable error)
  ;;

  let get_order =
    let ok = case `OK (Response.json (module Dto.Order)) in
    let not_found = case `Not_found (Response.json (module Dto.Api_response)) in
    let service_unavailable =
      case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    get / "store" / "order" /: arg "orderId" (module Http_parameter.Order_id)
    |> documented
         ~operation_id:"getOrderById"
         ~summary:"Find purchase order by ID."
         ~description:"Returns a stored purchase order."
    |> accepts Request.empty
    |> returns (ok <|> not_found <|> service_unavailable)
    ==> fun id database () ->
    let%bind result = Orders.find ~database id in
    match result with
    | Ok (Some order) -> respond ok (Dto.Order.of_domain order)
    | Ok None -> respond not_found (Dto.Api_response.order_not_found id)
    | Error error -> unavailable service_unavailable error
  ;;

  let delete_order =
    let ok = case `OK (Response.empty ~description:"Order deleted" ()) in
    let not_found = case `Not_found (Response.json (module Dto.Api_response)) in
    let service_unavailable =
      case `Service_unavailable (Response.json (module Dto.Api_response))
    in
    delete / "store" / "order" /: arg "orderId" (module Http_parameter.Order_id)
    |> documented
         ~operation_id:"deleteOrder"
         ~summary:"Delete purchase order by identifier."
         ~description:"Deletes a stored purchase order."
    |> accepts Request.empty
    |> returns (ok <|> not_found <|> service_unavailable)
    ==> fun id database () ->
    let%bind result = Orders.delete ~database id in
    match result with
    | Ok () -> respond ok ()
    | Error (`Not_found id) -> respond not_found (Dto.Api_response.order_not_found id)
    | Error (`Persistence error) -> unavailable service_unavailable error
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
