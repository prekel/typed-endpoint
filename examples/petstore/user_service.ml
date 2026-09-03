open! Base

type t = { users : (string, Domain.User.t) Hashtbl.t }
type error = [ `Not_found of string ]
type create_error = [ `Already_exists of string ]

let create () = { users = Hashtbl.create (module String) }

let add service user =
  if Hashtbl.mem service.users user.Domain.User.username then
    Error (`Already_exists user.username)
  else (
    Hashtbl.set service.users ~key:user.username ~data:user;
    Ok user)
;;

let duplicate_username service users =
  let seen = Hash_set.create (module String) in
  List.find_map users ~f:(fun user ->
    let username = user.Domain.User.username in
    if Hashtbl.mem service.users username || Hash_set.mem seen username then
      Some username
    else (
      Hash_set.add seen username;
      None))
;;

let add_many service users =
  match duplicate_username service users with
  | Some username -> Error (`Already_exists username)
  | None ->
    List.iter users ~f:(fun user ->
      Hashtbl.set service.users ~key:user.Domain.User.username ~data:user);
    Ok users
;;

let find service username = Hashtbl.find service.users username

let update service ~username user =
  if Hashtbl.mem service.users username then (
    let user = { user with Domain.User.username } in
    Hashtbl.set service.users ~key:username ~data:user;
    Ok user)
  else
    Error (`Not_found username)
;;

let delete service username =
  if Hashtbl.mem service.users username then (
    Hashtbl.remove service.users username;
    Ok ())
  else
    Error (`Not_found username)
;;

let authenticate service ~username ~password =
  match find service username with
  | None -> false
  | Some user ->
    Option.value_map
      user.Domain.User.attributes.password
      ~default:false
      ~f:(String.equal password)
;;
