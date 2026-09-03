open! Base

(** Default development composition root. It wires repository adapters and
    application services for the supplied backend effect. Production binaries
    can replace this functor with their own database-backed assembly. *)
module Make (Io : Base.Monad.S) : sig
  (** Pet service backed by an isolated in-memory repository. *)
  module Pets : Pet_service.S with type 'a io = 'a Io.t

  (** Order service wired to the same pet service instance. *)
  module Orders : Order_service.S with type 'a io = 'a Io.t

  (** User service backed by an isolated in-memory repository. *)
  module Users : User_service.S with type 'a io = 'a Io.t

  (** Complete application-scoped graph created by this composition root. *)
  type t = (Pets.t, Orders.t, Users.t) Services.t

  (** Creates one isolated graph. [Orders] receives the exact [Pets] instance,
      making the order-to-pet dependency visible at assembly time. *)
  val create : unit -> t
end
