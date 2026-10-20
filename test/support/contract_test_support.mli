(** Test-only inspection and validation of generated OpenAPI contracts.
    Assertion-style helpers raise on mismatches, while schema validation
    returns diagnostics for intentionally invalid fixtures. *)

open! Base

(** Test-only helpers for the subset emitted by typed-endpoint. Schema validation
    retains the whole document as the reference root; it does not flatten schemas.
    Embedded [$id] resources unsupported by the test validator return [Error].
    A resource can be checked separately with [document = schema]. *)
val validate
  :  document:Yojson.Safe.t
  -> schema:Yojson.Safe.t
  -> Yojson.Safe.t
  -> (unit, string) Result.t

(** Resolves local OpenAPI Reference Objects, applying description overrides,
    including empty strings. Never use this to resolve JSON Schema references. *)
val resolve_response_exn : Yojson.Safe.t -> Yojson.Safe.t -> Yojson.Safe.t

(** Lowercase OpenAPI operation key for a method. Extension methods are
    lowercased verbatim; this helper does not validate OpenAPI support. *)
val method_name : Typed_endpoint.Method.t -> string

(** Finds an emitted path template for a concrete target, preferring static
    segments over captures. An absent operation is a test failure. *)
val path_for_target_exn : Yojson.Safe.t -> meth:string -> target:string -> string

(** Returns an operation with effective parameters, including Path Item
    inheritance and operation overrides by [(name, in)]. *)
val operation_exn : Yojson.Safe.t -> path:string -> meth:string -> Yojson.Safe.t

(** Checks declared status, representation, required headers, and payload schema.
    Extra transport headers are allowed. Failures include the operation and status. *)
val response_exn
  :  document:Yojson.Safe.t
  -> path:string
  -> meth:string
  -> status:int
  -> headers:(string * string) list
  -> body:string
  -> unit

(** Validates a JSON request fixture intended to conform to the contract.
    Deliberately invalid requests must not be passed to this function. *)
val request_json_exn
  :  document:Yojson.Safe.t
  -> path:string
  -> meth:string
  -> media_type:string
  -> Yojson.Safe.t
  -> unit
