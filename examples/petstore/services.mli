open! Base

(** Application-scoped dependency container. Routes receive this value through
    [Typed_endpoint.Context], while each business service remains independently
    testable without an HTTP backend. *)

type t

(** Creates an isolated set of in-memory Petstore services. *)
val create : unit -> t

(** Pet aggregate service. *)
val pets : t -> Pet_service.t

(** Store-order aggregate service. *)
val orders : t -> Order_service.t

(** User aggregate service. *)
val users : t -> User_service.t
