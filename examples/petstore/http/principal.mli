open! Base

(** Credentials are distinct so a login session never inherits administrative
    authority from a demo bearer or API key. *)
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

(** Builds the administrative development identity. *)
val demo : unit -> t

(** Builds a user identity bound to a revocable login session. *)
val session : username:string -> token:string -> t

(** Builds the administrative API-key identity. *)
val api_key : unit -> t

(** Converts transport credentials into the domain's user-access policy. *)
val actor : t -> Domain.User.actor
