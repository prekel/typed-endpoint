open! Base

type undeclared_status =
  { meth : string
  ; path : string
  ; status : int
  ; declared : int list
  }

val ensure_declared
  :  meth:string
  -> path:string
  -> status:int
  -> declared:int list
  -> (unit, undeclared_status) Result.t
