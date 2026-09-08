open! Base

module type S = sig
  type 'a io
  type t
  type connection

  val with_connection
    :  t
    -> on_error:(Persistence_error.t -> 'error)
    -> f:(conn:connection -> ('a, 'error) Result.t io)
    -> ('a, 'error) Result.t io

  val transaction
    :  t
    -> on_error:(Persistence_error.t -> 'error)
    -> f:(conn:connection -> ('a, 'error) Result.t io)
    -> ('a, 'error) Result.t io
end
