open! Base

type credential =
  [ `Api_key
  | `Oauth
  ]

type identity =
  { subject : string
  ; credential : credential
  ; session_id : string option
  }

type t = identity Typed_endpoint.Principal.t

let oauth ?(subject = "demo-user") ?session_id ~scopes () =
  Typed_endpoint.Principal.v
    ~identity:{ subject; credential = `Oauth; session_id }
    ~scopes
    ()
;;

let api_key () =
  Typed_endpoint.Principal.v
    ~identity:{ subject = "petstore-client"; credential = `Api_key; session_id = None }
    ()
;;
