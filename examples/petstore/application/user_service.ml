open! Base

module type S = sig
  type 'a io
  type t

  val add
    :  t
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Already_exists of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val add_many
    :  t
    -> Domain.User.t list
    -> ( Domain.User.t list
         , [ `Already_exists of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val find : t -> string -> (Domain.User.t option, Persistence_error.t) Result.t io

  val update
    :  t
    -> username:string
    -> Domain.User.t
    -> ( Domain.User.t
         , [ `Not_found of string | `Persistence of Persistence_error.t ] )
         Result.t
         io

  val delete
    :  t
    -> string
    -> (unit, [ `Not_found of string | `Persistence of Persistence_error.t ]) Result.t io

  val authenticate
    :  t
    -> username:string
    -> password:string
    -> (bool, Persistence_error.t) Result.t io
end

module Make (Io : Base.Monad.S) (Repository : User_repository.S with type 'a io = 'a Io.t) =
struct
  type 'a io = 'a Io.t
  type t = { repository : Repository.t }

  let create ~repository = { repository }
  let add t = Repository.add t.repository
  let add_many t = Repository.add_many t.repository
  let find t = Repository.find t.repository
  let update t = Repository.update t.repository
  let delete t = Repository.delete t.repository
  let authenticate t = Repository.authenticate t.repository
end
