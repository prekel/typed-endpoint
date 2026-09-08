open! Base

(** Stateless application service for store orders. It defines the transaction
    boundary that covers both pet validation and order creation. *)
module type S = sig
  (** Effect shared by the database and repositories. *)
  type 'a io

  (** Runtime database resource supplied at the application boundary. *)
  type database

  (** Places an order only when its optional referenced pet exists. The check
      and write use the same transaction-scoped connection. *)
  val place
    :  database:database
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
  val find
    :  database:database
    -> int
    -> (Domain.Order.t option, Persistence_error.t) Result.t io

  (** Deletes one existing order in one transaction. *)
  val delete
    :  database:database
    -> int
    -> (unit, [ `Not_found of int | `Persistence of Persistence_error.t ]) Result.t io
end

(** Injects the database and both repository ports at compile time. The
    resulting module contains use-case functions but no service instance. *)
module Make
    (Io : Base.Monad.S)
    (Database : Database.S with type 'a io = 'a Io.t)
    (_ :
       Pet_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection)
    (_ :
       Order_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection) :
  S with type 'a io = 'a Io.t and type database = Database.t
