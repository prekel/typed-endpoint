open! Base

(** Authenticated Petstore caller carried by protected group contexts. *)
type credential =
  [ `Api_key
  | `Oauth
  ]

(** Application identity recorded for a successful authentication. *)
type identity =
  { subject : string
  ; credential : credential
  }

(** Principal carried by typed-endpoint request contexts. *)
type t = identity Typed_endpoint.Principal.t

(** Builds an OAuth principal with the scopes granted to the caller. *)
val oauth : scopes:string list -> unit -> t

(** Builds an API-key principal, which carries no OAuth scopes. *)
val api_key : unit -> t
