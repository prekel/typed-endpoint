open! Base

type page =
  { items : Domain.Article.t list
  ; page : int
  ; page_size : int
  ; total : int
  }

type t =
  { list : page:int -> page_size:int -> page
  ; find : int -> Domain.Article.t option
  ; create : author:string -> Domain.New_article.t -> (Domain.Article.t, string) Result.t
  ; delete : int -> bool
  }

let validate (article : Domain.New_article.t) =
  if String.is_empty (String.strip article.title) then
    Error "title must not be empty"
  else if String.is_empty (String.strip article.body) then
    Error "body must not be empty"
  else
    Ok article
;;

let in_memory store =
  let list ~page ~page_size =
    let articles = Article_store.list store in
    let total = List.length articles in
    let offset = (page - 1) * page_size in
    let items = List.take (List.drop articles offset) page_size in
    { items; page; page_size; total }
  in
  let create ~author article =
    Result.map (validate article) ~f:(Article_store.insert store ~author)
  in
  { list; find = Article_store.find store; create; delete = Article_store.delete store }
;;

let seeded () =
  let seed =
    [ Domain.Article.
        { id = 1
        ; title = "Typed routes"
        ; body = "One declaration drives runtime and OpenAPI."
        ; author = "alice"
        }
    ; Domain.Article.
        { id = 2
        ; title = "Portable handlers"
        ; body = "The application can run on several HTTP backends."
        ; author = "bob"
        }
    ]
  in
  Article_store.create ~seed () |> in_memory
;;
