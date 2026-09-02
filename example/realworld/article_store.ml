open! Base

type state =
  { next_id : int
  ; articles : Domain.Article.t list
  }

type t = state Atomic.t

let create ?(seed = []) () =
  let next_id =
    seed
    |> List.map ~f:(fun (article : Domain.Article.t) -> article.id)
    |> List.max_elt ~compare:Int.compare
    |> Option.value_map ~default:1 ~f:(fun id -> id + 1)
  in
  Atomic.make { next_id; articles = seed }
;;

let list store =
  (Atomic.get store).articles
  |> List.sort ~compare:(fun (left : Domain.Article.t) right ->
    Int.compare left.id right.id)
;;

let find store id =
  List.find (Atomic.get store).articles ~f:(fun article -> Int.equal article.id id)
;;

let rec update store ~f =
  let before = Atomic.get store in
  let after, result = f before in
  if Atomic.compare_and_set store before after then
    result
  else
    update store ~f
;;

let insert store ~author (new_article : Domain.New_article.t) =
  update store ~f:(fun state ->
    let article =
      Domain.Article.
        { id = state.next_id; title = new_article.title; body = new_article.body; author }
    in
    { next_id = state.next_id + 1; articles = article :: state.articles }, article)
;;

let delete store id =
  update store ~f:(fun state ->
    let articles =
      List.filter state.articles ~f:(fun article -> not (Int.equal article.id id))
    in
    let deleted = List.length articles < List.length state.articles in
    { state with articles }, deleted)
;;
