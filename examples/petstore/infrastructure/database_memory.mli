open! Base

(** Copy-on-write in-memory database used by examples and tests. Transactions
    commit atomically when their starting version is still current; otherwise
    they fail with an optimistic concurrency conflict. *)
module Make (Io : Base.Monad.S) : sig
  include Database.S with type 'a io = 'a Io.t

  (** Stateless pet repository over a connection scoped by this database. *)
  module Pet_repository :
    Pet_repository.S with type 'a io = 'a Io.t and type connection = connection

  (** Stateless order repository over a connection scoped by this database. *)
  module Order_repository :
    Order_repository.S with type 'a io = 'a Io.t and type connection = connection

  (** Stateless user repository over a connection scoped by this database. *)
  module User_repository :
    User_repository.S with type 'a io = 'a Io.t and type connection = connection

  (** Creates an empty isolated database. *)
  val create : unit -> t
end
