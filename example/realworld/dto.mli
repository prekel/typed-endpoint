open! Base
open Typed_endpoint

module Article : sig
  type t =
    { id : int
    ; title : string
    ; body : string
    ; author : string
    }

  val of_domain : Domain.Article.t -> t
  val to_yojson : t -> Yojson.Safe.t
  val metadata : t Metadata.t
end

module Article_page : sig
  type t =
    { items : Article.t list
    ; page : int
    ; page_size : int
    ; total : int
    }

  val of_domain : Article_service.page -> t
  val to_yojson : t -> Yojson.Safe.t
  val metadata : t Metadata.t
end

module Create_article : sig
  type t =
    { title : string
    ; body : string
    }

  val to_domain : t -> Domain.New_article.t
  val of_yojson : Yojson.Safe.t -> (t, string) Result.t
  val metadata : t Metadata.t
end

module Error : sig
  type t = { message : string }

  val v : string -> t
  val of_parse_error : Parse_error.t -> t
  val to_yojson : t -> Yojson.Safe.t
  val metadata : t Metadata.t
end
