open! Base

type credential =
  [ `Api_key
  | `Oauth
  ]

type identity =
  { subject : string
  ; credential : credential
  }

type t = identity Typed_endpoint.Principal.t

let oauth ~scopes () =
  Typed_endpoint.Principal.v
    ~identity:{ subject = "demo-user"; credential = `Oauth }
    ~scopes
    ()
;;

let api_key () =
  Typed_endpoint.Principal.v
    ~identity:{ subject = "petstore-client"; credential = `Api_key }
    ()
;;
