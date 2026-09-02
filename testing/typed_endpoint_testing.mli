open! Base

type request
type response
type app_builder

include
  Typed_endpoint.Backend.S
  with type req = request
   and type resp = response
   and type 'a io = 'a
   and type app_builder := app_builder

module Request : sig
  val v
    :  ?headers:(string * string) list
    -> ?body:string
    -> meth:meth
    -> target:string
    -> unit
    -> request

  val meth : request -> meth
  val target : request -> string
end

module Response : sig
  val status : response -> int
  val headers : response -> (string * string) list
  val body : response -> string
  val json : response -> (Yojson.Safe.t, string) Result.t
end

(** Dispatches a request through the compiled route table. A matching path with
    the wrong method returns 405; an unknown path returns 404. *)
val dispatch : app_builder -> request -> response
