open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson
open Typed_endpoint
open Make (Typed_endpoint_opium)
open D

(* ---------------- Params / Queries ---------------- *)

module User_id = struct
  type t = int [@@deriving jsonschema]

  let name = "user_id"

  let of_string s =
    try Ok (Int.of_string s) with
    | _ -> Error "not an int"
  ;;

  let metadata = Metadata.v ~description:"User id" ~tags:[ "params" ] ()
end

module Post_id = struct
  type t = string [@@deriving jsonschema]

  let name = "post_id"
  let of_string s = Ok s
  let metadata = Metadata.v ~description:"Post id" ~tags:[ "params" ] ()
end

module Q = struct
  type t = string [@@deriving jsonschema]

  let name = "q"

  let of_string s =
    if String.is_empty s then
      Error "empty q"
    else
      Ok s
  ;;

  let metadata = Metadata.v ~description:"Search query" ~tags:[ "queries" ] ()
end

module Page = struct
  type t = int [@@deriving jsonschema]

  let name = "page"

  let of_string s =
    try Ok (Int.of_string s) with
    | _ -> Error "page is not an int"
  ;;

  let metadata = Metadata.v ~description:"Page number" ~tags:[ "queries" ] ()
end

module Int_id = struct
  type t = int [@@deriving jsonschema]

  let of_string s =
    try Ok (Int.of_string s) with
    | _ -> Error "id is not an int"
  ;;

  let metadata = Metadata.v ~description:"Integer id" ~tags:[ "params" ] ()
end

module Mode = struct
  type t = string [@@deriving jsonschema]

  let of_string s =
    if String.is_empty s then
      Error "empty mode"
    else
      Ok s
  ;;

  let metadata = Metadata.v ~description:"Mode switcher" ~tags:[ "queries" ] ()
end

module Cover_page = struct
  type t = int [@@deriving jsonschema]

  let of_string s =
    try Ok (Int.of_string s) with
    | _ -> Error "page is not an int"
  ;;

  let metadata = Metadata.v ~description:"Page number" ~tags:[ "queries" ] ()
end

(* ---------------- Payloads ---------------- *)

type post =
  | Form1 of { text : string }
  (* | Form2 of post [@ref "post"] *)
  | Form3 of string
  | Form4
[@@deriving yojson, jsonschema]

module Create_post_rq = struct
  type t =
    { title : string
    ; body : string
    ; post : post
    }
  [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~description:"Create post request" ~tags:[ "body" ] ()
  let of_yojson = of_yojson
end

module Update_post_rq = struct
  type t =
    { title : string option
    ; body : string option
    }
  [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~description:"Update post request" ~tags:[ "body" ] ()
  let of_yojson = of_yojson
end

module Post_rs = struct
  type t =
    { id : string
    ; title : string
    ; post : post
    }
  [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~description:"Post response" ~tags:[ "responses" ] ()
end

module Post_list_rs = struct
  type t = { posts : Post_rs.t list } [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~description:"Posts list response" ~tags:[ "responses" ] ()
end

module Err_rs = struct
  type t = { error : string } [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~description:"Error response" ~tags:[ "errors" ] ()
end

let parse_error_message (error : Parse_error.t) = error.param ^ ": " ^ error.error

module Health_rs = struct
  type t = { status : string } [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~description:"Health response" ~tags:[ "misc" ] ()
end

module Json_ok = struct
  type t =
    { ok : bool
    ; msg : string
    }
  [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~description:"Ok payload" ~tags:[ "responses" ] ()
end

module Json_created = struct
  type t =
    { id : int
    ; note : string
    }
  [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~description:"Created payload" ~tags:[ "responses" ] ()
end

module Body_rq = struct
  type t =
    { kind : string
    ; n : int option
    }
  [@@deriving yojson, jsonschema]

  let metadata = Metadata.v ~description:"Body request" ~tags:[ "body" ] ()
  let of_yojson = of_yojson
end

module Err_envelope = struct
  type t =
    { data : Err_rs.t
    ; trace_id : string
    }
  [@@deriving to_yojson, jsonschema]

  let metadata =
    Metadata.v
      ~description:("Envelope(" ^ Err_rs.metadata.description ^ ")")
      ~tags:("wrapped" :: Err_rs.metadata.tags)
      ()
  ;;
end

module Nested_error_response = struct
  type t = { abc : Err_rs.t } [@@deriving to_yojson, jsonschema]

  let metadata = Err_rs.metadata
end

let parse_errors =
  Parse_error_response.json
    ~status:`Bad_request
    ~payload:(module Err_rs)
    ~map:(fun error -> Err_rs.{ error = parse_error_message error })
;;

(* ========================= *)
(* ===== Group 1: posts ==== *)
(* ========================= *)

(* 1) GET /users/:user_id/posts/:post_id?q=...&page=... -> OK(text) *)
let get_user_post_text =
  make
    ~meth:B.get
    ~description:"Get user post (text)"
    ~tags:[ "posts" ]
    ~path:
      (s "users"
       / param "user_id" (module User_id)
       / s "posts"
       / param "post_id" (module Post_id)
       / query "q" (module Q)
       / query "page" (module Page)
       /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"Plain text ok" ()))
  @@ fun user_id post_id q page (_req : B.req) () ->
  let q_s = Option.value q ~default:"<none>" in
  let page_s = Option.value_map page ~default:"<none>" ~f:Int.to_string in
  let msg =
    "user_id="
    ^ Int.to_string user_id
    ^ " post_id="
    ^ post_id
    ^ " q="
    ^ q_s
    ^ " page="
    ^ page_s
  in
  Lwt.return (OK ("ok: " ^ msg))
;;

(* 2) POST /users/:user_id/posts -> Created | Bad_request | Internal_server_error *)
let create_post =
  make
    ~meth:B.post
    ~description:"Create post"
    ~tags:[ "posts" ]
    ~operation_id:"createPost"
    ~request:(Request.json (module Create_post_rq))
    ~path:(s "users" / param "user_id" (module User_id) / s "posts" /? nil)
    ~responses:
      (created (Response.json (module Post_rs))
       |+ bad_request (Response.json (module Err_rs))
       |+ internal_server_error (Response.json (module Err_rs)))
  @@ fun user_id (_req : B.req) (rq : Create_post_rq.t) ->
  if String.is_empty rq.title then
    Lwt.return (Bad_request Err_rs.{ error = "title is empty" })
  else if Int.equal user_id 0 then
    Lwt.return (Internal_server_error Err_rs.{ error = "db down" })
  else (
    let id = Int.to_string user_id ^ "-" ^ rq.title in
    Lwt.return (Created Post_rs.{ id; title = rq.title; post = Form4 }))
;;

(* 3) DELETE /users/:user_id/posts/:post_id -> OK(204) | Not_found(404) *)
let delete_post =
  make
    ~meth:B.delete
    ~description:"Delete post"
    ~tags:[ "posts" ]
    ~request:Request.empty
    ~path:
      (s "users"
       / param "user_id" (module User_id)
       / s "posts"
       / param "post_id" (module Post_id)
       /? nil)
    ~responses:
      (no_content ~description:"Deleted"
       |+ not_found (Response.json (module Nested_error_response))
       |+ internal_server_error (Response.json (module Nested_error_response)))
  @@ fun (_user_id : User_id.t) (post_id : Post_id.t) (_req : B.req) () ->
  match post_id with
  | "missing" ->
    Lwt.return
      (Not_found Nested_error_response.{ abc = Err_rs.{ error = "post not found" } })
  | "internal" ->
    Lwt.return
      (Internal_server_error Nested_error_response.{ abc = Err_rs.{ error = "ise" } })
  | _ -> Lwt.return No_content
;;

let update_post =
  make
    ~meth:`PUT
    ~description:"Update post"
    ~tags:[ "posts" ]
    ~operation_id:"updatePost"
    ~request:(Request.json (module Update_post_rq))
    ~path:
      (s "users"
       / param "user_id" (module User_id)
       / s "posts"
       / param "post_id" (module Post_id)
       /? nil)
    ~responses:
      (ok (Response.json (module Post_rs))
       |+ not_found (Response.json (module Err_rs))
       |+ bad_request (Response.json (module Err_rs))
       |+ internal_server_error (Response.json (module Err_rs)))
  @@ fun user_id post_id _req rq ->
  if Int.equal user_id 0 then
    Lwt.return (Internal_server_error Err_rs.{ error = "db down" })
  else if String.equal post_id "missing" then
    Lwt.return (Not_found Err_rs.{ error = "post not found" })
  else (
    match
      rq.title, rq.body
    with
    | None, None -> Lwt.return (Bad_request Err_rs.{ error = "nothing to update" })
    | _ ->
      let title = Option.value rq.title ~default:"(unchanged)" in
      Lwt.return (OK Post_rs.{ id = post_id; title; post = Form4 }))
;;

let list_posts =
  make
    ~meth:B.get
    ~description:"List user posts"
    ~tags:[ "posts" ]
    ~request:Request.empty
    ~path:(s "users" / param "user_id" (module User_id) / s "posts" /? nil)
    ~responses:
      (ok (Response.json (module Post_list_rs))
       |+ not_found (Response.json (module Err_rs)))
  @@ fun (user_id : User_id.t) (_req : B.req) () ->
  match user_id with
  | 0 -> Lwt.return (Not_found Err_rs.{ error = "user not found" })
  | _ when user_id < 0 -> Lwt.return (Not_found Err_rs.{ error = "user not found" })
  | _ ->
    let posts =
      [ Post_rs.{ id = "p1"; title = "hello"; post = Form4 }
      ; Post_rs.{ id = "p2"; title = "world"; post = Form4 }
      ]
    in
    Lwt.return (OK Post_list_rs.{ posts })
;;

(* ============================== *)
(* ===== Group 2: cover-all ===== *)
(* ============================== *)

let cover_all =
  make
    ~meth:B.post
    ~description:"Route that exercises ALL response paths"
    ~tags:[ "cover-all" ]
    ~path:
      (s "cover"
       / param "id" (module Int_id)
       / query_req "mode" (module Mode)
       / query "page" (module Cover_page)
       /? nil)
    ~request:(Request.json (module Body_rq))
    ~responses:
      (JSON.ok (module Json_ok)
       |+ JSON.created (module Json_created)
       |+ code2xx
            [ `Accepted; `Non_authoritative_information; `Multi_status ]
            (Response.json (module Json_ok))
       |+ JSON.not_found (module Err_rs)
       |+ JSON.bad_request (module Err_rs)
       |+ code4xx
            [ `Conflict; `No_response; `Forbidden; `Unauthorized ]
            (Response.json (module Err_rs))
       |+ JSON.internal_server_error (module Err_rs)
       |+ code5xx
            [ `Bad_gateway; `Service_unavailable; `Gateway_timeout ]
            (Response.json (module Err_rs))
       |+ code
            [ `Code 418; `Code 499; `Not_modified ]
            (Response.json (module Err_envelope)))
  @@ fun id mode page _req body ->
  let _page = page in
  match mode with
  | "ok" -> Lwt.return (OK Json_ok.{ ok = true; msg = "OK: id=" ^ Int.to_string id })
  | "created" -> Lwt.return (Created Json_created.{ id; note = "Created" })
  | "2xx" -> Lwt.return (Code_2xx (`Accepted, Json_ok.{ ok = true; msg = "Accepted" }))
  | "nf" -> Lwt.return (Not_found Err_rs.{ error = "not found" })
  | "bad" -> Lwt.return (Bad_request Err_rs.{ error = "bad request" })
  | "4xx" -> Lwt.return (Code_4xx (`Conflict, Err_rs.{ error = "conflict" }))
  | "4xx-unlisted" -> Lwt.return (Code_4xx (`Gone, Err_rs.{ error = "gone" }))
  | "ise" -> Lwt.return (Internal_server_error Err_rs.{ error = "internal" })
  | "5xx" -> Lwt.return (Code_5xx (`Bad_gateway, Err_rs.{ error = "bad gateway" }))
  | "code-int" ->
    Lwt.return
      (Code
         ( `Code 499
         , Err_envelope.
             { data = Err_rs.{ error = "client closed request" }; trace_id = "trace-xyz" }
         ))
  | "code-status" ->
    Lwt.return
      (Code
         ( (`Not_modified :> B.status_code)
         , Err_envelope.
             { data = Err_rs.{ error = "not modified" }; trace_id = "trace-xyz" } ))
  | "validate-body" ->
    if String.is_empty body.kind then
      Lwt.return (Bad_request Err_rs.{ error = "kind is empty (validation)" })
    else
      Lwt.return (OK Json_ok.{ ok = true; msg = "validated" })
  | _ -> Lwt.return (Bad_request Err_rs.{ error = "unknown mode: " ^ mode })
;;

let cover_text =
  make
    ~meth:B.post
    ~description:"Plaintext echo (covers Request.PlainText + Response.PlainText)"
    ~tags:[ "cover-all" ]
    ~path:(s "cover" / s "text" /? nil)
    ~request:(Request.text ~description:"Plain text body")
    ~responses:(ok (Response.text ~description:"Plain text response" ()))
  @@ fun (_req : B.req) (body : string) -> Lwt.return (OK ("echo: " ^ body))
;;

let cover_empty =
  make
    ~meth:B.delete
    ~description:"Empty 204 (covers Response.Empty)"
    ~tags:[ "cover-all" ]
    ~path:(s "cover" / s "empty" /? nil)
    ~request:Request.empty
    ~responses:(no_content ~description:"No content")
  @@ fun (_req : B.req) () -> Lwt.return No_content
;;

let unsafe_raw =
  Unsafe.route ~meth:B.get ~path:"/unsafe/raw" ~handler:(fun _request ->
    B.respond_string ~status:`Forbidden "unsafe")
;;

let cover_json =
  make
    ~meth:B.get
    ~description:"Json not wrapped (covers Response.Json)"
    ~tags:[ "cover-all" ]
    ~path:(s "cover" / s "json" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.json (module Json_ok)))
  @@ fun (_req : B.req) () ->
  Lwt.return (OK Json_ok.{ ok = true; msg = "not wrapped json" })
;;

let echo_plain =
  make
    ~meth:B.post
    ~description:"Echo plain text"
    ~tags:[ "misc" ]
    ~request:(Request.text ~description:"Body as plain text")
    ~path:(s "echo" /? nil)
    ~responses:(ok (Response.text ~description:"Echo" ()))
  @@ fun (_req : B.req) (body : string) -> Lwt.return (OK ("echo: " ^ body))
;;

let health =
  make
    ~meth:B.get
    ~description:"Health check"
    ~tags:[ "misc" ]
    ~request:Request.empty
    ~path:(s "health" /? nil)
    ~responses:(ok (Response.json (module Health_rs)))
  @@ fun (_req : B.req) () -> Lwt.return (OK Health_rs.{ status = "ok" })
;;

(* ---------------- Groups ---------------- *)

let groups : Group.t list =
  [ Group.v
      ~prefix:[ "v1" ]
      ~metadata:(Metadata.v ~description:"Posts API (v1)" ~tags:[ "posts" ] ())
      [ get_user_post_text; create_post; delete_post; update_post; list_posts ]
  ; Group.v
      ~prefix:[ "v1" ]
      ~metadata:
        (Metadata.v
           ~description:"Coverage / demo endpoints (v1)"
           ~tags:[ "cover-all" ]
           ())
      [ cover_all; cover_text; cover_empty; cover_json; echo_plain; health; unsafe_raw ]
  ]
;;

(* Call generation: *)
let compiled = D.compile_exn ~parse_error:parse_errors groups
let openapi : Yojson.Safe.t = Compiled.openapi compiled
let app : B.app_builder = Compiled.app compiled

let%expect_test "openapi snapshot" =
  Stdlib.Printf.printf "%s" (Yojson.Safe.pretty_to_string openapi);
  [%expect
    {|
    {
      "openapi": "3.1.0",
      "info": { "title": "API", "version": "0.1.0" },
      "tags": [
        { "name": "posts", "description": "Posts API (v1)" },
        { "name": "cover-all", "description": "Coverage / demo endpoints (v1)" }
      ],
      "paths": {
        "/v1/users/{user_id}/posts/{post_id}": {
          "delete": {
            "description": "Delete post",
            "tags": [ "posts" ],
            "parameters": [
              {
                "name": "user_id",
                "in": "path",
                "required": true,
                "description": "User id",
                "schema": { "type": "integer" }
              },
              {
                "name": "post_id",
                "in": "path",
                "required": true,
                "description": "Post id",
                "schema": { "type": "string" }
              }
            ],
            "responses": {
              "204": { "description": "Deleted" },
              "404": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "abc": {
                          "type": "object",
                          "properties": { "error": { "type": "string" } },
                          "required": [ "error" ],
                          "additionalProperties": false
                        }
                      },
                      "required": [ "abc" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "500": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "abc": {
                          "type": "object",
                          "properties": { "error": { "type": "string" } },
                          "required": [ "error" ],
                          "additionalProperties": false
                        }
                      },
                      "required": [ "abc" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "400": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              }
            }
          },
          "get": {
            "description": "Get user post (text)",
            "tags": [ "posts" ],
            "parameters": [
              {
                "name": "user_id",
                "in": "path",
                "required": true,
                "description": "User id",
                "schema": { "type": "integer" }
              },
              {
                "name": "post_id",
                "in": "path",
                "required": true,
                "description": "Post id",
                "schema": { "type": "string" }
              },
              {
                "name": "q",
                "in": "query",
                "required": false,
                "description": "Search query",
                "schema": { "type": "string" }
              },
              {
                "name": "page",
                "in": "query",
                "required": false,
                "description": "Page number",
                "schema": { "type": "integer" }
              }
            ],
            "responses": {
              "200": {
                "description": "Plain text ok",
                "content": { "text/plain": { "schema": { "type": "string" } } }
              },
              "400": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              }
            }
          },
          "put": {
            "description": "Update post",
            "tags": [ "posts" ],
            "operationId": "updatePost",
            "requestBody": {
              "required": true,
              "description": "Update post request",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "body": { "type": [ "string", "null" ] },
                      "title": { "type": [ "string", "null" ] }
                    },
                    "required": [ "body", "title" ],
                    "additionalProperties": false
                  }
                }
              }
            },
            "parameters": [
              {
                "name": "user_id",
                "in": "path",
                "required": true,
                "description": "User id",
                "schema": { "type": "integer" }
              },
              {
                "name": "post_id",
                "in": "path",
                "required": true,
                "description": "Post id",
                "schema": { "type": "string" }
              }
            ],
            "responses": {
              "200": {
                "description": "Post response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "post": {
                          "anyOf": [
                            {
                              "type": "array",
                              "prefixItems": [
                                { "const": "Form1" },
                                {
                                  "type": "object",
                                  "properties": { "text": { "type": "string" } },
                                  "required": [ "text" ],
                                  "additionalProperties": false
                                }
                              ],
                              "unevaluatedItems": false,
                              "minItems": 2,
                              "maxItems": 2
                            },
                            {
                              "type": "array",
                              "prefixItems": [
                                { "const": "Form3" }, { "type": "string" }
                              ],
                              "unevaluatedItems": false,
                              "minItems": 2,
                              "maxItems": 2
                            },
                            {
                              "type": "array",
                              "prefixItems": [ { "const": "Form4" } ],
                              "unevaluatedItems": false,
                              "minItems": 1,
                              "maxItems": 1
                            }
                          ]
                        },
                        "title": { "type": "string" },
                        "id": { "type": "string" }
                      },
                      "required": [ "post", "title", "id" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "404": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "400": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "500": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              }
            }
          }
        },
        "/v1/echo": {
          "post": {
            "description": "Echo plain text",
            "tags": [ "cover-all", "misc" ],
            "requestBody": {
              "required": true,
              "description": "Body as plain text",
              "content": { "text/plain": { "schema": { "type": "string" } } }
            },
            "parameters": [],
            "responses": {
              "200": {
                "description": "Echo",
                "content": { "text/plain": { "schema": { "type": "string" } } }
              }
            }
          }
        },
        "/v1/users/{user_id}/posts": {
          "get": {
            "description": "List user posts",
            "tags": [ "posts" ],
            "parameters": [
              {
                "name": "user_id",
                "in": "path",
                "required": true,
                "description": "User id",
                "schema": { "type": "integer" }
              }
            ],
            "responses": {
              "200": {
                "description": "Posts list response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "posts": {
                          "type": "array",
                          "items": {
                            "type": "object",
                            "properties": {
                              "post": {
                                "anyOf": [
                                  {
                                    "type": "array",
                                    "prefixItems": [
                                      { "const": "Form1" },
                                      {
                                        "type": "object",
                                        "properties": {
                                          "text": { "type": "string" }
                                        },
                                        "required": [ "text" ],
                                        "additionalProperties": false
                                      }
                                    ],
                                    "unevaluatedItems": false,
                                    "minItems": 2,
                                    "maxItems": 2
                                  },
                                  {
                                    "type": "array",
                                    "prefixItems": [
                                      { "const": "Form3" }, { "type": "string" }
                                    ],
                                    "unevaluatedItems": false,
                                    "minItems": 2,
                                    "maxItems": 2
                                  },
                                  {
                                    "type": "array",
                                    "prefixItems": [ { "const": "Form4" } ],
                                    "unevaluatedItems": false,
                                    "minItems": 1,
                                    "maxItems": 1
                                  }
                                ]
                              },
                              "title": { "type": "string" },
                              "id": { "type": "string" }
                            },
                            "required": [ "post", "title", "id" ],
                            "additionalProperties": false
                          }
                        }
                      },
                      "required": [ "posts" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "404": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "400": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              }
            }
          },
          "post": {
            "description": "Create post",
            "tags": [ "posts" ],
            "operationId": "createPost",
            "requestBody": {
              "required": true,
              "description": "Create post request",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "post": {
                        "anyOf": [
                          {
                            "type": "array",
                            "prefixItems": [
                              { "const": "Form1" },
                              {
                                "type": "object",
                                "properties": { "text": { "type": "string" } },
                                "required": [ "text" ],
                                "additionalProperties": false
                              }
                            ],
                            "unevaluatedItems": false,
                            "minItems": 2,
                            "maxItems": 2
                          },
                          {
                            "type": "array",
                            "prefixItems": [
                              { "const": "Form3" }, { "type": "string" }
                            ],
                            "unevaluatedItems": false,
                            "minItems": 2,
                            "maxItems": 2
                          },
                          {
                            "type": "array",
                            "prefixItems": [ { "const": "Form4" } ],
                            "unevaluatedItems": false,
                            "minItems": 1,
                            "maxItems": 1
                          }
                        ]
                      },
                      "body": { "type": "string" },
                      "title": { "type": "string" }
                    },
                    "required": [ "post", "body", "title" ],
                    "additionalProperties": false
                  }
                }
              }
            },
            "parameters": [
              {
                "name": "user_id",
                "in": "path",
                "required": true,
                "description": "User id",
                "schema": { "type": "integer" }
              }
            ],
            "responses": {
              "201": {
                "description": "Post response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "post": {
                          "anyOf": [
                            {
                              "type": "array",
                              "prefixItems": [
                                { "const": "Form1" },
                                {
                                  "type": "object",
                                  "properties": { "text": { "type": "string" } },
                                  "required": [ "text" ],
                                  "additionalProperties": false
                                }
                              ],
                              "unevaluatedItems": false,
                              "minItems": 2,
                              "maxItems": 2
                            },
                            {
                              "type": "array",
                              "prefixItems": [
                                { "const": "Form3" }, { "type": "string" }
                              ],
                              "unevaluatedItems": false,
                              "minItems": 2,
                              "maxItems": 2
                            },
                            {
                              "type": "array",
                              "prefixItems": [ { "const": "Form4" } ],
                              "unevaluatedItems": false,
                              "minItems": 1,
                              "maxItems": 1
                            }
                          ]
                        },
                        "title": { "type": "string" },
                        "id": { "type": "string" }
                      },
                      "required": [ "post", "title", "id" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "400": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "500": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              }
            }
          }
        },
        "/v1/health": {
          "get": {
            "description": "Health check",
            "tags": [ "cover-all", "misc" ],
            "parameters": [],
            "responses": {
              "200": {
                "description": "Health response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "status": { "type": "string" } },
                      "required": [ "status" ],
                      "additionalProperties": false
                    }
                  }
                }
              }
            }
          }
        },
        "/v1/cover/empty": {
          "delete": {
            "description": "Empty 204 (covers Response.Empty)",
            "tags": [ "cover-all" ],
            "parameters": [],
            "responses": { "204": { "description": "No content" } }
          }
        },
        "/v1/cover/json": {
          "get": {
            "description": "Json not wrapped (covers Response.Json)",
            "tags": [ "cover-all" ],
            "parameters": [],
            "responses": {
              "200": {
                "description": "Ok payload",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "msg": { "type": "string" },
                        "ok": { "type": "boolean" }
                      },
                      "required": [ "msg", "ok" ],
                      "additionalProperties": false
                    }
                  }
                }
              }
            }
          }
        },
        "/v1/cover/{id}": {
          "post": {
            "description": "Route that exercises ALL response paths",
            "tags": [ "cover-all" ],
            "requestBody": {
              "required": true,
              "description": "Body request",
              "content": {
                "application/json": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "n": { "type": [ "integer", "null" ] },
                      "kind": { "type": "string" }
                    },
                    "required": [ "n", "kind" ],
                    "additionalProperties": false
                  }
                }
              }
            },
            "parameters": [
              {
                "name": "id",
                "in": "path",
                "required": true,
                "description": "Integer id",
                "schema": { "type": "integer" }
              },
              {
                "name": "mode",
                "in": "query",
                "required": true,
                "description": "Mode switcher",
                "schema": { "type": "string" }
              },
              {
                "name": "page",
                "in": "query",
                "required": false,
                "description": "Page number",
                "schema": { "type": "integer" }
              }
            ],
            "responses": {
              "200": {
                "description": "Ok payload",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "msg": { "type": "string" },
                        "ok": { "type": "boolean" }
                      },
                      "required": [ "msg", "ok" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "201": {
                "description": "Created payload",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "note": { "type": "string" },
                        "id": { "type": "integer" }
                      },
                      "required": [ "note", "id" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "202": {
                "description": "Ok payload",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "msg": { "type": "string" },
                        "ok": { "type": "boolean" }
                      },
                      "required": [ "msg", "ok" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "203": {
                "description": "Ok payload",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "msg": { "type": "string" },
                        "ok": { "type": "boolean" }
                      },
                      "required": [ "msg", "ok" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "207": {
                "description": "Ok payload",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "msg": { "type": "string" },
                        "ok": { "type": "boolean" }
                      },
                      "required": [ "msg", "ok" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "404": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "400": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "409": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "444": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "403": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "401": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "500": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "502": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "503": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "504": {
                "description": "Error response",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": { "error": { "type": "string" } },
                      "required": [ "error" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "418": {
                "description": "Envelope(Error response)",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "trace_id": { "type": "string" },
                        "data": {
                          "type": "object",
                          "properties": { "error": { "type": "string" } },
                          "required": [ "error" ],
                          "additionalProperties": false
                        }
                      },
                      "required": [ "trace_id", "data" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "499": {
                "description": "Envelope(Error response)",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "trace_id": { "type": "string" },
                        "data": {
                          "type": "object",
                          "properties": { "error": { "type": "string" } },
                          "required": [ "error" ],
                          "additionalProperties": false
                        }
                      },
                      "required": [ "trace_id", "data" ],
                      "additionalProperties": false
                    }
                  }
                }
              },
              "304": {
                "description": "Envelope(Error response)",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "trace_id": { "type": "string" },
                        "data": {
                          "type": "object",
                          "properties": { "error": { "type": "string" } },
                          "required": [ "error" ],
                          "additionalProperties": false
                        }
                      },
                      "required": [ "trace_id", "data" ],
                      "additionalProperties": false
                    }
                  }
                }
              }
            }
          }
        },
        "/v1/cover/text": {
          "post": {
            "description": "Plaintext echo (covers Request.PlainText + Response.PlainText)",
            "tags": [ "cover-all" ],
            "requestBody": {
              "required": true,
              "description": "Plain text body",
              "content": { "text/plain": { "schema": { "type": "string" } } }
            },
            "parameters": [],
            "responses": {
              "200": {
                "description": "Plain text response",
                "content": { "text/plain": { "schema": { "type": "string" } } }
              }
            }
          }
        }
      }
    }
    |}]
;;
