open! Base

type undeclared_response_case =
  { meth : string
  ; path : string
  ; status : int
  ; declared : int list
  }

let ensure_declared_case ~meth ~path ~case_id ~declared_case_ids ~status ~declared =
  if List.mem declared_case_ids case_id ~equal:Int.equal then
    Ok ()
  else
    Error { meth; path; status; declared }
;;
