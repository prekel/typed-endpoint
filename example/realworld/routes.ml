open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson
open Typed_endpoint

module type Request = sig
  type t

  val header : t -> string -> string option
end

module Make (B : Backend.S) (Backend_request : Request with type t = B.req) = struct
  module Endpoint = Typed_endpoint.Make (B)
  open Endpoint
  open D

  module Positive_int = struct
    type t = int [@@deriving jsonschema]

    let of_string value =
      match Stdlib.int_of_string_opt value with
      | Some value when value > 0 -> Ok value
      | _ -> Error "expected a positive integer"
    ;;

    let metadata : t Metadata.t =
      Metadata.v
        ~schema:t_jsonschema
        ~description:"A positive integer"
        ~tags:[ "parameters" ]
        ()
    ;;
  end

  let parse_error =
    Parse_error_response.json
      ~status:`Bad_request
      ~payload:(module Dto.Error)
      ~map:Dto.Error.of_parse_error
  ;;

  let service_context service = Dependency.value service

  let authenticated =
    Guard.v
      ~status:`Unauthorized
      ~response:(Response.json (module Dto.Error))
      ~check:(fun request ->
        let result =
          match Backend_request.header request "authorization" with
          | Some "Bearer demo-token" -> Ok "demo-user"
          | _ -> Error (Dto.Error.v "missing or invalid bearer token")
        in
        B.return result)
  ;;

  let list_articles service =
    make_with
      ~context:(service_context service)
      ~meth:B.get
      ~summary:"List articles"
      ~description:"Returns a stable, paginated article collection."
      ~tags:[ "articles" ]
      ~operation_id:"listArticles"
      ~path:(s "articles" / query "page" (module Positive_int) /? nil)
      ~request:Request.empty
      ~responses:(ok (Response.json (module Dto.Article_page)))
    @@ fun page service () ->
    let page = Option.value page ~default:1 in
    service.Article_service.list ~page ~page_size:10 |> Dto.Article_page.of_domain
    |> fun result -> B.return (OK result)
  ;;

  let get_article service =
    make_with
      ~context:(service_context service)
      ~meth:B.get
      ~summary:"Get an article"
      ~description:"Looks up one article by its numeric identifier."
      ~tags:[ "articles" ]
      ~operation_id:"getArticle"
      ~path:(s "articles" / param "id" (module Positive_int) /? nil)
      ~request:Request.empty
      ~responses:
        (ok (Response.json (module Dto.Article))
         |+ not_found (Response.json (module Dto.Error)))
    @@ fun id service () ->
    match service.Article_service.find id with
    | Some article -> B.return (OK (Dto.Article.of_domain article))
    | None -> B.return (Not_found (Dto.Error.v "article not found"))
  ;;

  let create_article service =
    let context = Context.both authenticated (service_context service) in
    make_with
      ~context
      ~meth:B.post
      ~summary:"Create an article"
      ~description:"Creates an article for the authenticated demo user."
      ~tags:[ "articles" ]
      ~operation_id:"createArticle"
      ~path:(s "articles" /? nil)
      ~request:(Request.json (module Dto.Create_article))
      ~responses:
        (created (Response.json (module Dto.Article))
         |+ bad_request (Response.json (module Dto.Error)))
    @@ fun (author, service) request ->
    match
      service.Article_service.create ~author (Dto.Create_article.to_domain request)
    with
    | Ok article -> B.return (Created (Dto.Article.of_domain article))
    | Error message -> B.return (Bad_request (Dto.Error.v message))
  ;;

  let delete_article service =
    let context = Context.both authenticated (service_context service) in
    make_with
      ~context
      ~meth:B.delete
      ~summary:"Delete an article"
      ~description:"Deletes an article after bearer-token authentication."
      ~tags:[ "articles" ]
      ~operation_id:"deleteArticle"
      ~path:(s "articles" / param "id" (module Positive_int) /? nil)
      ~request:Request.empty
      ~responses:
        (no_content ~description:"Article deleted"
         |+ not_found (Response.json (module Dto.Error)))
    @@ fun id (_author, service) () ->
    if service.Article_service.delete id then
      B.return No_content
    else
      B.return (Not_found (Dto.Error.v "article not found"))
  ;;

  let compile service =
    let routes =
      [ list_articles service
      ; get_article service
      ; create_article service
      ; delete_article service
      ]
    in
    [ Group.v
        ~prefix:[ "api" ]
        ~metadata:
          (Operation_metadata.v
             ~description:"A backend-independent article API"
             ~tags:[ "articles" ]
             ())
        routes
    ]
    |> compile_exn ~parse_error
  ;;
end
