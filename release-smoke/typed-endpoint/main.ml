open! Base
open Typed_endpoint

module Person = struct
  type t = { name : string } [@@deriving yojson, jsonschema]

  let t_jsonschema : t Json_schema.t =
    Json_schema.with_openapi ~description:"Person" t_jsonschema
  ;;
end

module Endpoint = Make (Typed_endpoint_testing)
open Endpoint

let route =
  get / "health"
  |> documented ~operation_id:"health"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Health status" ()))
  ==> fun ok () () -> respond ok "ok"
;;

let routes =
  compile_exn
    [ Group.make_with_context
        ~context:(Context.return ())
        ~description:"Release smoke"
        [ route ]
    ]
  |> Compiled.app
;;

let () =
  ignore Person.t_jsonschema;
  ignore routes
;;
