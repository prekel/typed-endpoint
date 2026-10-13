open! Base

(** Stateless session use cases; login and logout define transaction boundaries. *)
module type S = sig
  type 'a io
  type database

  val login
    :  database:database
    -> username:string
    -> password:string
    -> (Domain.Session.t option, Persistence_error.t) Result.t io

  (** Expired tokens never resolve to an identity. *)
  val find
    :  database:database
    -> string
    -> (Domain.Session.t option, Persistence_error.t) Result.t io

  val logout : database:database -> string -> (bool, Persistence_error.t) Result.t io
end

(** All dependencies, including clock and entropy, are selected statically. *)
module Make
    (Io : Base.Monad.S)
    (Database : Database.S with type 'a io = 'a Io.t)
    (_ :
       User_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection)
    (_ :
       Session_repository.S
       with type 'a io = 'a Io.t
        and type connection = Database.connection)
    (_ : Session_runtime.S) : S with type 'a io = 'a Io.t and type database = Database.t
