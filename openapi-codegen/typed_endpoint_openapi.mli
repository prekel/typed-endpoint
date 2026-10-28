open! Base

module Diagnostic : sig
  (** [path] is a JSON Pointer into the input or configuration. *)
  type t =
    { path : string
    ; code : string
    ; message : string
    }

  val to_string : t -> string
end

module Config : sig
  type t

  (** No metadata selectors; names and identities come from operation locations. *)
  val default : t

  val of_yojson : Yojson.Safe.t -> (t, Diagnostic.t list) Result.t
end

module Source : sig
  (** [name] identifies a document in diagnostics and scopes anonymous schemas.
      Use stable, unique names. [group] overrides grouping by URL segment without
      changing routes. Schema identities selected by [Config] are shared across
      documents; anonymous schemas remain local to each document. *)
  type t =
    { name : string
    ; group : string option
    ; document : Yojson.Safe.t
    }
end

module Generated_file : sig
  (** Paths are fixed relative filenames, never paths derived from input metadata. *)
  type t =
    { path : string
    ; contents : string
    }
end

(** Pure generation from dereferenced OpenAPI 3.0.3 or 3.2.1. Unsupported constructs
    return diagnostics before the caller writes any files. *)
val generate
  :  ?config:Config.t
  -> Yojson.Safe.t
  -> (Generated_file.t list, Diagnostic.t list) Result.t

(** Generates one shared DTO graph and server from all documents. Repeated
    identities must have compatible schemas. Duplicate routes and operation IDs
    are rejected across documents. Sources are sorted by name for reproducibility;
    [Server.openapi_config] uses the first source's document metadata. Each
    generated group also exposes [openapi_config] from its first source. *)
val generate_sources
  :  ?config:Config.t
  -> Source.t list
  -> (Generated_file.t list, Diagnostic.t list) Result.t
