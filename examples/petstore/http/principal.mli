open! Base

(** Authenticated Petstore caller carried by protected group contexts. *)
type credential =
  [ `Api_key
  | `Oauth
  ]

type identity =
  { subject : string
  ; credential : credential
  }

type t = identity Typed_endpoint.Principal.t

val oauth : scopes:string list -> unit -> t
val api_key : unit -> t
