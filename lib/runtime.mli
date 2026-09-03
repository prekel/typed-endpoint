open! Base

(** Details of a handler response whose status is absent from the endpoint's
    typed response declaration. [declared] is the exact set of status codes
    accepted for the selected response constructor. *)
type undeclared_status =
  { meth : string
  ; path : string
  ; status : int
  ; declared : int list
  }

(** [ensure_declared ~meth ~path ~status ~declared] succeeds exactly when
    [status] occurs in [declared]. On failure it preserves the supplied route
    identity, returned status, and declaration in the error value so callers
    can turn the invariant violation into a backend-independent diagnostic. *)
val ensure_declared
  :  meth:string
  -> path:string
  -> status:int
  -> declared:int list
  -> (unit, undeclared_status) Result.t
