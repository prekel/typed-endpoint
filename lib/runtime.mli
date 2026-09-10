open! Base

(** Details of a handler response whose case token is absent from the
    endpoint's response declaration. [declared] lists the endpoint's numeric
    statuses for diagnostics. *)
type undeclared_response_case =
  { meth : string
  ; path : string
  ; status : int
  ; declared : int list
  }

(** [ensure_declared_case] compares opaque case identities rather than numeric
    statuses, so a different token for the same status is still rejected. *)
val ensure_declared_case
  :  meth:string
  -> path:string
  -> case_id:int
  -> declared_case_ids:int list
  -> status:int
  -> declared:int list
  -> (unit, undeclared_response_case) Result.t
