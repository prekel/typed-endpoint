open! Base

module Status = struct
  type t =
    | Available
    | Pending
    | Sold

  let equal left right =
    match left, right with
    | Available, Available | Pending, Pending | Sold, Sold -> true
    | _ -> false
  ;;
end

module Category = struct
  type t =
    { id : int option
    ; name : string option
    }
end

module Tag = struct
  type t =
    { id : int option
    ; name : string option
    }
end

module Pet = struct
  type attributes =
    { name : string
    ; category : Category.t option
    ; photo_urls : string list
    ; tags : Tag.t list option
    ; status : Status.t option
    }

  type t =
    { id : int
    ; attributes : attributes
    }
end

module Order = struct
  module Status = struct
    type t =
      | Placed
      | Approved
      | Delivered

    let equal left right =
      match left, right with
      | Placed, Placed | Approved, Approved | Delivered, Delivered -> true
      | _ -> false
    ;;
  end

  type attributes =
    { pet_id : int option
    ; quantity : int option
    ; ship_date : string option
    ; status : Status.t option
    ; complete : bool option
    }

  type t =
    { id : int
    ; attributes : attributes
    }
end

module User = struct
  type attributes =
    { id : int option
    ; first_name : string option
    ; last_name : string option
    ; email : string option
    ; password : string option
    ; phone : string option
    ; user_status : int option
    }

  type t =
    { username : string
    ; attributes : attributes
    }
end

module Page_request = struct
  type t =
    { page : int
    ; limit : int
    }

  let default_page = 1
  let default_limit = 20
  let max_page = 1_000_000
  let max_limit = 100

  let create ~page ~limit =
    if page < 1 || page > max_page then
      Error ("page must be between 1 and " ^ Int.to_string max_page)
    else if limit < 1 || limit > max_limit then
      Error ("limit must be between 1 and " ^ Int.to_string max_limit)
    else
      Ok { page; limit }
  ;;

  let page t = t.page
  let limit t = t.limit
end

module Page = struct
  type 'a t =
    { items : 'a list
    ; page : int
    ; limit : int
    ; total : int
    ; total_pages : int
    }
end
