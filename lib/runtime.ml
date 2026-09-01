open! Base

type undeclared_status =
  { meth : string
  ; path : string
  ; status : int
  ; declared : int list
  }

let ensure_declared ~meth ~path ~status ~declared =
  if List.mem declared status ~equal:Int.equal then
    Ok ()
  else
    Error { meth; path; status; declared }
;;
