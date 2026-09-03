open! Base

(** Application service for store orders. Besides its repository, it receives
    the pet service explicitly so the referenced-pet invariant stays in the
    application layer rather than an HTTP controller. *)
module type S = sig
  (** Effect shared with the injected repositories and services. *)
  type 'a io

  (** Order service instance. *)
  type t

  (** Places an order only when its optional referenced pet exists. *)
  val place
    :  t
    -> ?id:int
    -> Domain.Order.attributes
    -> ( Domain.Order.t
         , [ `Already_exists of int
           | `Pet_not_found of int
           | `Persistence of Persistence_error.t
           ] )
         Result.t
         io

  (** Finds one order; absence is not a persistence error. *)
  val find : t -> int -> (Domain.Order.t option, Persistence_error.t) Result.t io

  (** Deletes one existing order. *)
  val delete
    :  t
    -> int
    -> (unit, [ `Not_found of int | `Persistence of Persistence_error.t ]) Result.t io
end

(** Injects both repository and application-service dependencies. A database
    adapter such as a PG/Lwt repository can be supplied without changing this
    service or its controllers. *)
module Make
    (Io : Base.Monad.S)
    (Repository : Order_repository.S with type 'a io = 'a Io.t)
    (Pets : Pet_service.S with type 'a io = 'a Io.t) : sig
  include S with type 'a io = 'a Io.t

  (** Creates an order service with all dependencies supplied explicitly. *)
  val create : repository:Repository.t -> pets:Pets.t -> t
end
