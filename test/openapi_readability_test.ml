open! Base
open Typed_endpoint
module B = Typed_endpoint_testing
module E = Make (B)
open E

let member = Yojson.Safe.Util.member
let print json = Stdlib.print_endline (Yojson.Safe.to_string json)

module Pet = struct
  type t = { name : string } [@@deriving to_yojson, jsonschema]

  let t_jsonschema =
    Json_schema.with_openapi ~schema_name:"Pet" ~description:"Pet found" t_jsonschema
  ;;
end

let identifier =
  Parameter.v
    ~schema:(Json_schema.integer ~format:`Int64 ~minimum:1 ())
    ~description:"Pet identifier"
    ~of_string:(fun value ->
      match Int.of_string_opt value with
      | Some value -> Ok value
      | None -> Error "Invalid identifier")
    ()
;;

let get_pet =
  get / "pet" /: arg "petId" identifier
  |> documented ~operation_id:"getPetById" ~summary:"Get pet" ~description:"Returns a pet"
  |> accepts Request.empty
  |> returns (case `OK (Response.json (module Pet)))
  ==> fun id ok () () -> respond ok Pet.{ name = Int.to_string id }
;;

let update_pet =
  post
  / "pet"
  /: arg "petId" identifier
  /? arg "name" (Parameter.string ~description:"Updated name" ())
  |> documented ~summary:"Update pet" ~description:"Update pet"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Pet updated" ()))
  ==> fun _id name ok () () -> respond ok (Option.value name ~default:"pet")
;;

let delete_pet =
  delete / "pet" /: arg "petId" identifier
  |> documented ~summary:"Delete pet" ~description:"Delete pet"
  |> accepts Request.empty
  |> returns (case `OK (Response.empty ~description:"Pet deleted" ()))
  ==> fun _id ok () () -> respond ok ()
;;

let compiled routes =
  compile_exn
    [ Group.make_with_context ~context:(Context.return ()) ~description:"Pets" routes ]
;;

let pets = compiled [ get_pet; update_pet; delete_pet ]
let doc = Compiled.openapi pets
let path = doc |> member "paths" |> member "/pet/{petId}"

let%expect_test "common path parameters appear once before operations" =
  path |> member "parameters" |> print;
  [%expect
    {| [{"name":"petId","in":"path","required":true,"description":"Pet identifier","schema":{"type":"integer","format":"int64","minimum":1}}] |}];
  path |> member "get" |> member "parameters" |> print;
  [%expect {| null |}];
  path |> member "post" |> member "parameters" |> print;
  [%expect
    {| [{"name":"name","in":"query","required":false,"description":"Updated name","schema":{"type":"string"}}] |}];
  path |> member "delete" |> member "parameters" |> print;
  [%expect {| null |}];
  let response = B.Client.call (Compiled.app pets) `GET "/pet/7" in
  assert (B.Response.status response = 200);
  assert (String.equal (B.Response.body response) {|{"name":"7"}|})
;;

let%expect_test "responses stay inline while DTO schemas have readable names" =
  path |> member "get" |> member "responses" |> member "200" |> print;
  [%expect
    {| {"description":"Pet found","content":{"application/json":{"schema":{"$ref":"#/components/schemas/Pet"}}}} |}];
  path |> member "delete" |> member "responses" |> member "200" |> print;
  [%expect {| {"description":"Pet deleted"} |}];
  doc |> member "components" |> member "responses" |> print;
  [%expect {| null |}]
;;

let%expect_test "summary and description keep only useful differences" =
  path |> member "get" |> member "description" |> print;
  [%expect {| "Returns a pet" |}];
  path |> member "post" |> member "summary" |> print;
  [%expect {| "Update pet" |}];
  path |> member "post" |> member "description" |> print;
  [%expect {| null |}];
  let only =
    Compiled.openapi (compiled [ get_pet ]) |> member "paths" |> member "/pet/{petId}"
  in
  assert (Poly.equal (member "parameters" only) `Null);
  assert (
    Poly.equal
      (member "get" only |> member "parameters" |> Yojson.Safe.Util.to_list |> List.length)
      1)
;;

module Count = struct
  type t = int [@@deriving to_yojson, jsonschema]

  let t_jsonschema =
    Json_schema.with_openapi ~schema_name:"Count" ~description:"Count" t_jsonschema
  ;;
end

module Pets = struct
  type t = Pet.t list [@@deriving to_yojson, jsonschema]

  let t_jsonschema =
    Json_schema.with_openapi ~schema_name:"Pets" ~description:"Pets" t_jsonschema
  ;;
end

module Holder = struct
  type t =
    { count : int
    ; pets : Pet.t list
    }
  [@@deriving to_yojson, jsonschema]

  let t_jsonschema = Json_schema.with_openapi ~description:"Holder" t_jsonschema
end

let json_route (type a) name (module P : Response_payload.S with type t = a) value =
  get / name
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.json (module P)))
  ==> fun ok () () -> respond ok value
;;

let%expect_test "OpenAPI preserves DTO field declaration order" =
  let schema =
    compiled [ json_route "holder" (module Holder) Holder.{ count = 1; pets = [] } ]
    |> Compiled.openapi
    |> member "paths"
    |> member "/holder"
    |> member "get"
    |> member "responses"
    |> member "200"
    |> member "content"
    |> member "application/json"
    |> member "schema"
  in
  schema
  |> member "properties"
  |> Yojson.Safe.Util.to_assoc
  |> List.map ~f:(fun (name, _) -> `String name)
  |> (fun names -> `List names)
  |> print;
  [%expect {| ["count","pets"] |}];
  schema |> member "required" |> print;
  [%expect {| ["count","pets"] |}]
;;

let%expect_test
    "anonymous primitives and collections stay inline despite named equivalents"
  =
  let doc =
    compiled
      [ json_route "count" (module Count) 1
      ; json_route "pets" (module Pets) []
      ; json_route "holder" (module Holder) Holder.{ count = 1; pets = [] }
      ; get_pet
      ]
    |> Compiled.openapi
  in
  let schema path =
    doc
    |> member "paths"
    |> member path
    |> member "get"
    |> member "responses"
    |> member "200"
    |> member "content"
    |> member "application/json"
    |> member "schema"
  in
  schema "/holder" |> member "properties" |> member "count" |> print;
  [%expect {| {"type":"integer"} |}];
  schema "/holder" |> member "properties" |> member "pets" |> print;
  [%expect {| {"type":"array","items":{"$ref":"#/components/schemas/Pet"}} |}];
  schema "/count" |> print;
  [%expect {| {"$ref":"#/components/schemas/Count"} |}];
  schema "/pets" |> print;
  [%expect {| {"$ref":"#/components/schemas/Pets"} |}]
;;

module Generic_payload = struct
  type 'a box = { value : 'a } [@@deriving yojson, jsonschema]
  type t = int box [@@deriving yojson, jsonschema]
end

let%expect_test "generic schema constants preserve OpenAPI and codec behavior" =
  let route =
    post / "generic"
    |> documented
    |> accepts (Request.json (module Generic_payload))
    |> returns (case `OK (Response.json (module Generic_payload)))
    ==> fun ok () body ->
    let open Io.Let_syntax in
    let%bind result = Request_body.read body in
    match result with
    | Ok value -> respond ok value
    | Error error -> Request_body.reject error
  in
  let api = compiled [ route ] in
  let operation =
    Compiled.openapi api |> member "paths" |> member "/generic" |> member "post"
  in
  let field_schema content =
    content
    |> member "content"
    |> member "application/json"
    |> member "schema"
    |> member "properties"
    |> member "value"
  in
  operation |> member "requestBody" |> field_schema |> print;
  [%expect {| true |}];
  operation |> member "responses" |> member "200" |> field_schema |> print;
  [%expect {| true |}];
  let call body =
    B.Client.call
      ~headers:[ "Content-Type", "application/json" ]
      ~body
      (Compiled.app api)
      `POST
      "/generic"
  in
  let response = call {|{"value":42}|} in
  assert (B.Response.status response = 200);
  assert (String.equal (B.Response.body response) {|{"value":42}|});
  assert (B.Response.status (call {|{"value":"wrong"}|}) = 400)
;;
