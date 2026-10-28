open! Base

module Mapping_error : sig
  type segment =
    | Field of string
    | Index of int

  type t

  (** Does not capture the input value. Messages should avoid sensitive data. *)
  val make : code:string -> message:string -> t

  val path : t -> segment list
  val code : t -> string
  val message : t -> string

  (** Prefixes the target field to an existing error path. *)
  val at_field : string -> ('a, t) Result.t -> ('a, t) Result.t

  val at_index : int -> ('a, t) Result.t -> ('a, t) Result.t
  val to_string : t -> string
end

module Converter : sig
  type ('a, 'b) t = 'a -> ('b, Mapping_error.t) Result.t

  val of_total : ('a -> 'b) -> ('a, 'b) t
  val option : ('a, 'b) t -> ('a option, 'b option) t

  (** Visits elements in order, stopping at the first error, prefixed by index. *)
  val list : ('a, 'b) t -> ('a list, 'b list) t

  val array : ('a, 'b) t -> ('a array, 'b array) t
end
