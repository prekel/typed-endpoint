open! Base

(** [render ~config contract] produces an OpenAPI 3.1 JSON document from a
    successfully compiled contract. Typed path segments are converted from the
    router's [:name] notation to OpenAPI's [{name}] notation. Named schemas and
    security schemes are emitted as components, while runtime-only unsafe
    routes are omitted. Paths, methods, responses, and components are rendered
    in a deterministic order. *)
val render : config:Contract.Openapi.Config.t -> Contract.Compiled.t -> Yojson.Safe.t
