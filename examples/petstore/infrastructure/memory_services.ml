open! Base

module Make (Io : Base.Monad.S) = struct
  module Pet_repository = Pet_repository_memory.Make (Io)
  module Pets = Pet_service.Make (Io) (Pet_repository)
  module Order_repository = Order_repository_memory.Make (Io)
  module Orders = Order_service.Make (Io) (Order_repository) (Pets)
  module User_repository = User_repository_memory.Make (Io)
  module Users = User_service.Make (Io) (User_repository)

  type t = (Pets.t, Orders.t, Users.t) Services.t

  let create () =
    let pets = Pets.create ~repository:(Pet_repository.create ()) in
    let orders = Orders.create ~repository:(Order_repository.create ()) ~pets in
    let users = Users.create ~repository:(User_repository.create ()) in
    Services.v ~pets ~orders ~users
  ;;
end
