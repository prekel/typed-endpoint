(** Internal OpenAPI 3.1 renderer for validated contracts. Rendering is pure
    and deterministic and does not inspect handlers or backend route values. *)

open! Base

(** [render ~config contract] produces an OpenAPI 3.1 JSON document from a
    successfully compiled contract. Typed path segments are converted from the
    router's [:name] notation to OpenAPI's [{name}] notation. Named schemas and
    security schemes are emitted as components, while runtime-only unsafe
    routes are omitted. Paths, methods, responses, and components are rendered
    in a deterministic order. Nested copies of registered ordinary object
    schemas reuse their component names; anonymous primitives and collections,
    and all Response Objects, remain inline. Identical path parameters shared
    by every operation are lifted to the Path Item. Empty parameter and required
    lists, empty operation descriptions, and descriptions equal to the summary
    are omitted. Resource scopes are preserved. *)
val render : config:Contract.Openapi.Config.t -> Contract.Compiled.t -> Yojson.Safe.t
