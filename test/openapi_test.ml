open! Base
open Typed_endpoint
module E = Make (Typed_endpoint_testing)
open E

let member = Yojson.Safe.Util.member
let print json = Stdlib.print_endline (Yojson.Safe.to_string json)

let resolve document json =
  let rec loop seen json =
    match member "$ref" json with
    | `String reference when String.is_prefix reference ~prefix:"#/components/responses/"
      -> Contract_test_support.resolve_response_exn document json
    | `String reference when String.is_prefix reference ~prefix:"#/" ->
      assert (not (List.mem seen reference ~equal:String.equal));
      let path = String.chop_prefix_exn reference ~prefix:"#/" |> String.split ~on:'/' in
      let target = List.fold path ~init:document ~f:(fun json name -> member name json) in
      loop (reference :: seen) target
    | _ -> json
  in
  loop [] json
;;

let operation document path =
  document |> member "paths" |> member ("/" ^ path) |> member "get"
;;

let response_schema document path =
  operation document path
  |> member "responses"
  |> member "200"
  |> resolve document
  |> member "content"
  |> member "application/json"
  |> member "schema"
;;

let group routes =
  Group.make_with_context
    ~context:(Context.return ())
    ~description:"OpenAPI regressions"
    routes
;;

let document routes = compile_exn [ group routes ] |> Compiled.openapi

let json_route (type a) path (module P : Response_payload.S with type t = a) value =
  get / path
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.json (module P)))
  ==> fun ok () () -> respond ok value
;;

module Item = struct
  type t = { name : string }
  [@@deriving to_yojson, jsonschema] [@@jsonschema.disallow_extra_fields]

  let t_jsonschema =
    Json_schema.with_openapi ~schema_name:"Item" ~description:"An item" t_jsonschema
  ;;
end

module Items = struct
  type t = Item.t list [@@deriving to_yojson, jsonschema]

  let t_jsonschema = Json_schema.with_openapi ~description:"Items" t_jsonschema
end

module Holder = struct
  type t = { item : Item.t } [@@deriving to_yojson, jsonschema]

  let t_jsonschema =
    Json_schema.with_openapi ~schema_name:"Holder" ~description:"Holder" t_jsonschema
  ;;
end

let item = Item.{ name = "cat" }

let item_routes =
  [ json_route "item" (module Item) item
  ; json_route "other" (module Item) item
  ; json_route "items" (module Items) [ item ]
  ; json_route "holder" (module Holder) Holder.{ item }
  ]
;;

let validates document schema json =
  let fields = Yojson.Safe.Util.to_assoc document in
  let root = `Assoc (("allOf", `List [ schema ]) :: fields) in
  let basic json = Yojson.Basic.from_string (Yojson.Safe.to_string json) in
  match Jsonschema.create_validator_from_json ~schema:(basic root) () with
  | Error error ->
    Stdlib.failwith (Stdlib.Format.asprintf "%a" Jsonschema.pp_compile_error error)
  | Ok validator -> Result.is_ok (Jsonschema.validate validator (basic json))
;;

let%expect_test "named models are reused in collection and component properties" =
  let doc = document item_routes in
  response_schema doc "items" |> member "items" |> print;
  [%expect {| {"$ref":"#/components/schemas/Item"} |}];
  doc
  |> member "components"
  |> member "schemas"
  |> member "Holder"
  |> member "properties"
  |> member "item"
  |> print;
  [%expect {| {"$ref":"#/components/schemas/Item"} |}];
  assert (validates doc (response_schema doc "items") (Items.to_yojson [ item ]));
  assert (not (validates doc (response_schema doc "items") (`List [ `Assoc [] ])))
;;

let%test_unit "canonical output is independent of route declaration order" =
  assert (Yojson.Safe.equal (document item_routes) (document (List.rev item_routes)))
;;

module Alias = struct
  include Item

  let t_jsonschema =
    Json_schema.with_openapi ~schema_name:"Alias" ~description:"An alias" t_jsonschema
  ;;
end

module Annotated = struct
  type t = { name : string [@jsonschema.description "A distinct annotation"] }
  [@@deriving to_yojson, jsonschema] [@@jsonschema.disallow_extra_fields]

  let t_jsonschema = Json_schema.with_openapi ~description:"Annotated" t_jsonschema
end

let%expect_test "explicit names survive while unnamed copies choose a stable alias" =
  let doc =
    document
      (json_route "alias" (module Alias) item
       :: json_route "annotated" (module Annotated) Annotated.{ name = "cat" }
       :: item_routes)
  in
  response_schema doc "item" |> print;
  [%expect {| {"$ref":"#/components/schemas/Item"} |}];
  response_schema doc "alias" |> print;
  [%expect {| {"$ref":"#/components/schemas/Alias"} |}];
  response_schema doc "items" |> member "items" |> print;
  [%expect {| {"$ref":"#/components/schemas/Alias"} |}];
  response_schema doc "annotated"
  |> member "properties"
  |> member "name"
  |> member "description"
  |> print;
  [%expect {| "A distinct annotation" |}]
;;

let%expect_test "identical responses stay inline with readable schema references" =
  let doc = document item_routes in
  let response path = operation doc path |> member "responses" |> member "200" in
  assert (Yojson.Safe.equal (response "item") (response "other"));
  doc |> member "components" |> member "responses" |> print;
  [%expect {| null |}];
  response "item" |> print;
  [%expect
    {| {"description":"An item","content":{"application/json":{"schema":{"$ref":"#/components/schemas/Item"}}}} |}];
  assert (validates doc (response_schema doc "item") (Item.to_yojson item))
;;

let text_route path description =
  get / path
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description ()))
  ==> fun ok () () -> respond ok "ok"
;;

let%expect_test "inline responses preserve their individual descriptions" =
  let doc = document [ text_route "one" "First"; text_route "two" "Second" ] in
  operation doc "one" |> member "parameters" |> print;
  [%expect {| null |}];
  operation doc "one"
  |> member "responses"
  |> member "200"
  |> member "description"
  |> print;
  [%expect {| "First" |}];
  let first = operation doc "one" |> member "responses" |> member "200" in
  let second = operation doc "two" |> member "responses" |> member "200" in
  assert (Yojson.Safe.equal (member "$ref" first) `Null);
  assert (Yojson.Safe.equal (member "$ref" second) `Null);
  assert (Yojson.Safe.equal (doc |> member "components") `Null);
  assert (
    Yojson.Safe.equal (resolve doc second |> member "description") (`String "Second"))
;;

module Text_json = struct
  type t = string [@@deriving to_yojson, jsonschema]

  let t_jsonschema =
    Json_schema.with_openapi ~description:"Shared description" t_jsonschema
  ;;
end

let%test_unit "inline responses retain content and header differences" =
  let response header_name =
    let header = Header.required header_name (Header.string ~description:"Mode" ()) in
    Response.with_header header (Response.text ~description:"Shared description" ())
  in
  let with_header path name =
    get / path
    |> documented
    |> accepts Request.empty
    |> returns (case `OK (response name))
    ==> fun ok () () -> respond ok ("mode", "ok")
  in
  let doc =
    document
      [ text_route "text" "Shared description"
      ; json_route "json" (module Text_json) "ok"
      ; with_header "header" "x-mode"
      ; with_header "other-header" "x-other"
      ]
  in
  List.iter [ "text"; "json"; "header"; "other-header" ] ~f:(fun path ->
    assert (
      Yojson.Safe.equal
        (operation doc path |> member "responses" |> member "200" |> member "$ref")
        `Null));
  assert (Yojson.Safe.equal (doc |> member "components") `Null)
;;

(* Imported schema fixtures exercise reference scopes and literal annotations;
   they are not modifications of a derived DTO schema. *)
module Literal = struct
  type t = Yojson.Safe.t

  let to_yojson value = value

  let schema : t Json_schema.t =
    Json_schema.Unsafe.of_yojson
      (`Assoc
          [ "type", `String "object"
          ; "properties", `Assoc []
          ; "required", `List []
          ; "default", `Assoc [ "required", `List []; "type", `String "object" ]
          ; "examples", `List [ `Assoc [ "required", `List [] ] ]
          ])
  ;;

  let t_jsonschema = Json_schema.with_openapi ~description:"Literal annotations" schema
end

let%expect_test "empty required is omitted while literal annotations are preserved" =
  let doc = document [ json_route "literal" (module Literal) (`Assoc []) ] in
  response_schema doc "literal" |> print;
  [%expect
    {| {"type":"object","properties":{},"default":{"required":[],"type":"object"},"examples":[{"required":[]}]} |}]
;;

module Resource = struct
  type t = Yojson.Safe.t

  let to_yojson value = value

  let schema : t Json_schema.t =
    Json_schema.Unsafe.of_yojson
      (`Assoc
          [ "$id", `String "urn:typed-endpoint:resource-test"
          ; "$defs", `Assoc [ "value", Json_schema.to_yojson Item.t_jsonschema ]
          ; "type", `String "object"
          ; ( "properties"
            , `Assoc
                [ "value", `Assoc [ "$ref", `String "#/$defs/value" ]
                ; "inline", Json_schema.to_yojson Item.t_jsonschema
                ] )
          ])
  ;;

  let t_jsonschema =
    Json_schema.with_openapi ~schema_name:"Resource" ~description:"A resource" schema
  ;;
end

let%test_unit "resource identifiers and local references are not rewritten" =
  let doc =
    document
      [ json_route "item" (module Item) item
      ; json_route "resource" (module Resource) (`Assoc [])
      ]
  in
  assert (
    Yojson.Safe.equal
      (doc |> member "components" |> member "schemas" |> member "Resource")
      (Json_schema.to_yojson Resource.schema));
  assert (
    validates
      doc
      (response_schema doc "resource")
      (`Assoc [ "value", Item.to_yojson item; "inline", Item.to_yojson item ]))
;;

let strings = Parameter.string ~description:"An element" ()
let integers = Parameter.int ~description:"An integer" ()

let filter_domain =
  `Assoc
    [ ( "fields"
      , `Assoc [ "name", `Assoc [ "type", `String "string"; "required", `List [] ] ] )
    ; "operators", `List [ `String "eq"; `String "and" ]
    ; "$ref", `String "#/filter-language/Pet"
    ]
;;

let filter_schema =
  Json_schema.string ~min_length:1 ()
  |> Json_schema.with_extension ~name:"x-domain" ~value:filter_domain
;;

let filter_route ?schema_name path =
  let parameter =
    Parameter.v
      ~schema:filter_schema
      ?schema_name
      ~description:"Pet filter expression"
      ~of_string:Result.return
      ()
  in
  get / path /! arg "filter" parameter
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Filter expression" ()))
  ==> fun filter ok () () -> respond ok filter
;;

let filter_query_schema doc path =
  operation doc path
  |> member "parameters"
  |> Yojson.Safe.Util.to_list
  |> List.hd_exn
  |> member "schema"
;;

let%expect_test
    "inline query extensions preserve opaque language metadata and string values"
  =
  let compiled = compile_exn [ group [ filter_route "filter" ] ] in
  let doc = Compiled.openapi compiled in
  filter_query_schema doc "filter" |> print;
  [%expect
    {| {"x-domain":{"fields":{"name":{"type":"string","required":[]}},"operators":["eq","and"],"$ref":"#/filter-language/Pet"},"type":"string","minLength":1} |}];
  let response =
    Typed_endpoint_testing.Client.call
      (Compiled.app compiled)
      `GET
      "/filter?filter=name%20eq%20%22cat%22%20and%20name%20eq%20%22dog%22"
  in
  assert (Typed_endpoint_testing.Response.status response = 200);
  assert (
    String.equal
      (Typed_endpoint_testing.Response.body response)
      {|name eq "cat" and name eq "dog"|})
;;

let%expect_test "named query schemas keep extensions in their OpenAPI component" =
  let doc = document [ filter_route ~schema_name:"PetFilter" "named-filter" ] in
  filter_query_schema doc "named-filter" |> print;
  [%expect {| {"$ref":"#/components/schemas/PetFilter"} |}];
  doc |> member "components" |> member "schemas" |> member "PetFilter" |> print;
  [%expect
    {| {"x-domain":{"fields":{"name":{"type":"string","required":[]}},"operators":["eq","and"],"$ref":"#/filter-language/Pet"},"type":"string","minLength":1} |}]
;;

let collection_route path codec =
  get / path /! query_arg "tags" codec
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Elements" ()))
  ==> fun values ok () () -> respond ok (String.concat ~sep:"|" values)
;;

let%expect_test "CSV and repeated codecs share their wire contract with OpenAPI" =
  let csv = collection_route "csv" (Query.csv ~description:"CSV" strings) in
  let repeated =
    collection_route "repeated" (Query.repeated ~description:"Repeated" strings)
  in
  let compiled = compile_exn [ group [ csv; repeated ] ] in
  let doc = Compiled.openapi compiled in
  let show path =
    operation doc path
    |> member "parameters"
    |> Yojson.Safe.Util.to_list
    |> List.hd_exn
    |> print
  in
  show "csv";
  [%expect
    {| {"name":"tags","in":"query","required":true,"description":"CSV","schema":{"type":"array","items":{"type":"string"}},"style":"form","explode":false} |}];
  show "repeated";
  [%expect
    {| {"name":"tags","in":"query","required":true,"description":"Repeated","schema":{"type":"array","items":{"type":"string"}},"style":"form","explode":true} |}];
  let call target =
    Typed_endpoint_testing.Client.call (Compiled.app compiled) `GET target
  in
  let csv_response = call "/csv?tags=cat,dog" in
  assert (Typed_endpoint_testing.Response.status csv_response = 200);
  assert (String.equal (Typed_endpoint_testing.Response.body csv_response) "cat|dog");
  let repeated_response = call "/repeated?tags=cat%2Cdog&tags=bird" in
  assert (Typed_endpoint_testing.Response.status repeated_response = 200);
  assert (
    String.equal (Typed_endpoint_testing.Response.body repeated_response) "cat,dog|bird");
  assert (Typed_endpoint_testing.Response.status (call "/csv?tags=cat&tags=dog") = 400);
  assert (Typed_endpoint_testing.Response.status (call "/csv") = 400)
;;

let%test_unit "optional collection codecs distinguish absence from a present empty value" =
  let route =
    get / "optional" /? query_arg "n" (Query.repeated ~description:"Numbers" integers)
    |> documented
    |> accepts Request.empty
    |> returns (case `OK (Response.text ~description:"Numbers" ()))
    ==> fun values ok () () ->
    respond
      ok
      (match values with
       | None -> "absent"
       | Some values -> List.map values ~f:Int.to_string |> String.concat ~sep:",")
  in
  let compiled = compile_exn [ group [ route ] ] in
  let call target =
    Typed_endpoint_testing.Client.call (Compiled.app compiled) `GET target
  in
  assert (String.equal (Typed_endpoint_testing.Response.body (call "/optional")) "absent");
  assert (
    String.equal (Typed_endpoint_testing.Response.body (call "/optional?n=2&n=1")) "2,1");
  assert (Typed_endpoint_testing.Response.status (call "/optional?n=") = 400);
  assert (Typed_endpoint_testing.Response.status (call "/optional?n=1&n=bad") = 400)
;;

let%test_unit "array schemas cannot silently use a scalar query decoder" =
  let check schema of_string =
    let codec = Parameter.v ~schema ~description:"Legacy CSV" ~of_string () in
    let route =
      get / "legacy" /! arg "tags" codec
      |> documented
      |> accepts Request.empty
      |> returns (case `OK (Response.empty ~description:"Empty" ()))
      ==> fun _ ok () () -> respond ok ()
    in
    match compile [ group [ route ] ] with
    | Ok _ -> assert false
    | Error errors ->
      assert (
        List.exists errors ~f:(function
          | Compile_error.Array_query_requires_codec { name = "tags"; _ } -> true
          | _ -> false))
  in
  let schema = Json_schema.list ~items:(Json_schema.string ()) () in
  check schema (fun value -> Ok (String.split value ~on:','));
  check (Json_schema.nullable schema) (fun value ->
    Ok (Some (String.split value ~on:',')))
;;
