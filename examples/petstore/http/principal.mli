(** Authenticated Petstore identities and their domain authorization policy.
    Session credentials identify one user; development credentials carry
    administrative authority. *)

open! Base

(** Credentials are distinct so a login session never inherits administrative
    authority from a demo bearer or API key. *)
type credential =
  [ `Api_key
  | `Demo_bearer
  | `Session
  ]

(** Authenticated subject and credential provenance. Constructors attach
    [session_id = Some token] only to session identities; development identities
    carry [None]. The session token remains a private authentication credential. *)
type identity =
  { subject : string
  ; credential : credential
  ; session_id : string option
  }

(** Typed principal passed from HTTP guards to secured controller contexts.
    {!actor} derives authority from credential provenance, not the subject name. *)
type t = identity Typed_endpoint.Principal.t

(** Builds the administrative development identity. *)
val demo : unit -> t

(** Builds a user identity bound to a revocable login session. *)
val session : username:string -> token:string -> t

(** Builds the administrative API-key identity. *)
val api_key : unit -> t

(** Converts transport credentials into the domain's user-access policy. *)
val actor : t -> Domain.User.actor
