open! Base
open Ppx_deriving_jsonschema_runtime.Primitives.Yojson
open Typed_endpoint

module Article = struct
  type t =
    { id : int
    ; title : string
    ; body : string
    ; author : string
    }
  [@@deriving yojson, jsonschema]

  let of_domain (article : Domain.Article.t) =
    { id = article.id
    ; title = article.title
    ; body = article.body
    ; author = article.author
    }
  ;;

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"An article" ~tags:[ "articles" ] ()
  ;;
end

module Article_page = struct
  type t =
    { items : Article.t list
    ; page : int
    ; page_size : int
    ; total : int
    }
  [@@deriving yojson, jsonschema]

  let of_domain (result : Article_service.page) =
    { items = List.map result.items ~f:Article.of_domain
    ; page = result.page
    ; page_size = result.page_size
    ; total = result.total
    }
  ;;

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:t_jsonschema
      ~description:"A page of articles"
      ~tags:[ "articles" ]
      ()
  ;;
end

module Create_article = struct
  type t =
    { title : string
    ; body : string
    }
  [@@deriving yojson, jsonschema]

  let to_domain (article : t) =
    Domain.New_article.{ title = article.title; body = article.body }
  ;;

  let metadata : t Metadata.t =
    Metadata.v
      ~schema:t_jsonschema
      ~description:"Fields required to create an article"
      ~tags:[ "articles" ]
      ()
  ;;
end

module Error = struct
  type t = { message : string } [@@deriving yojson, jsonschema]

  let v message = { message }
  let of_parse_error (error : Parse_error.t) = v (error.param ^ ": " ^ error.error)

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"API error" ~tags:[ "errors" ] ()
  ;;
end
