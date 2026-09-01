open! Base

val render : ?title:string -> ?version:string -> Contract.Compiled.t -> Yojson.Safe.t
