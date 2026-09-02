open! Base

(** A small concurrent in-memory repository. The immutable state is replaced
    atomically, so the same implementation can be used by all example servers. *)
type t

val create : ?seed:Domain.Article.t list -> unit -> t
val list : t -> Domain.Article.t list
val find : t -> int -> Domain.Article.t option
val insert : t -> author:string -> Domain.New_article.t -> Domain.Article.t
val delete : t -> int -> bool
