open! Base

(** Converts schema positions only, bundles local resources, and rewrites tuple
    keywords for json-schema-to-typescript. References must resolve within the
    supplied document; unsupported resource scopes return a diagnostic. *)
val schema : Yojson.Safe.t -> (Yojson.Safe.t, string) Result.t
