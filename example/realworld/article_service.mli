open! Base

type page =
  { items : Domain.Article.t list
  ; page : int
  ; page_size : int
  ; total : int
  }

(** Application port injected into HTTP handlers. Tests may provide these
    functions directly; [in_memory] is the runnable example implementation. *)
type t =
  { list : page:int -> page_size:int -> page
  ; find : int -> Domain.Article.t option
  ; create : author:string -> Domain.New_article.t -> (Domain.Article.t, string) Result.t
  ; delete : int -> bool
  }

val in_memory : Article_store.t -> t
val seeded : unit -> t
