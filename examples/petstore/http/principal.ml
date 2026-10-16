open! Base

type credential =
  [ `Api_key
  | `Demo_bearer
  | `Session
  ]

type identity =
  { subject : string
  ; credential : credential
  ; session_id : string option
  }

type t = identity Typed_endpoint.Principal.t

let demo () =
  Typed_endpoint.Principal.v
    ~identity:{ subject = "demo-user"; credential = `Demo_bearer; session_id = None }
    ()
;;

let session ~username ~token =
  Typed_endpoint.Principal.v
    ~identity:{ subject = username; credential = `Session; session_id = Some token }
    ()
;;

let api_key () =
  Typed_endpoint.Principal.v
    ~identity:{ subject = "petstore-client"; credential = `Api_key; session_id = None }
    ()
;;

let actor principal =
  let identity = Typed_endpoint.Principal.identity principal in
  match identity.credential with
  | `Session -> Domain.User.Session_user identity.subject
  | `Api_key | `Demo_bearer -> Domain.User.Administrator
;;
