open! Base

type t =
  { bearer_token : string
  ; api_key : string
  }

let getenv_or_default name default = Stdlib.Sys.getenv_opt name |> Option.value ~default

let from_env_exn () =
  let api_key = getenv_or_default "PETSTORE_API_KEY" "demo-key" in
  if String.is_empty api_key then
    invalid_arg "PETSTORE_API_KEY must not be empty";
  { bearer_token = getenv_or_default "PETSTORE_BEARER_TOKEN" "demo-token"; api_key }
;;

let bearer_token value =
  match String.lsplit2 value ~on:' ' with
  | Some (scheme, token) when String.Caseless.equal scheme "bearer" ->
    let token = String.lstrip token ~drop:(Char.equal ' ') in
    let body, padding =
      match String.lsplit2 token ~on:'=' with
      | None -> token, ""
      | Some (body, padding) -> body, padding
    in
    if
      (not (String.is_empty body))
      && String.for_all body ~f:(fun char ->
        Char.is_alphanum char || String.mem "-._~+/" char)
      && String.for_all padding ~f:(Char.equal '=')
    then
      Some token
    else
      None
  | _ -> None
;;
