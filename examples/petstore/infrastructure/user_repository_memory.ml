open! Base

module Make (Io : Base.Monad.S) = struct
  type 'a io = 'a Io.t
  type t = { users : (string, Domain.User.t) Hashtbl.t }

  type error =
    [ `Not_found of string
    | `Persistence of Persistence_error.t
    ]

  type create_error =
    [ `Already_exists of string
    | `Persistence of Persistence_error.t
    ]

  let create () = { users = Hashtbl.create (module String) }

  let add repository user =
    Io.return
      (if Hashtbl.mem repository.users user.Domain.User.username then
         Error (`Already_exists user.username)
       else (
         Hashtbl.set repository.users ~key:user.username ~data:user;
         Ok user))
  ;;

  let duplicate_username repository users =
    let seen = Hash_set.create (module String) in
    List.find_map users ~f:(fun user ->
      let username = user.Domain.User.username in
      if Hashtbl.mem repository.users username || Hash_set.mem seen username then
        Some username
      else (
        Hash_set.add seen username;
        None))
  ;;

  let add_many repository users =
    Io.return
      (match duplicate_username repository users with
       | Some username -> Error (`Already_exists username)
       | None ->
         List.iter users ~f:(fun user ->
           Hashtbl.set repository.users ~key:user.Domain.User.username ~data:user);
         Ok users)
  ;;

  let find repository username = Io.return (Ok (Hashtbl.find repository.users username))

  let update repository ~username user =
    Io.return
      (if Hashtbl.mem repository.users username then (
         let user = { user with Domain.User.username } in
         Hashtbl.set repository.users ~key:username ~data:user;
         Ok user)
       else
         Error (`Not_found username))
  ;;

  let delete repository username =
    Io.return
      (if Hashtbl.mem repository.users username then (
         Hashtbl.remove repository.users username;
         Ok ())
       else
         Error (`Not_found username))
  ;;

  let authenticate repository ~username ~password =
    Hashtbl.find repository.users username
    |> Option.value_map ~default:false ~f:(fun user ->
      Option.value_map
        user.Domain.User.attributes.password
        ~default:false
        ~f:(String.equal password))
    |> Result.return
    |> Io.return
  ;;
end
