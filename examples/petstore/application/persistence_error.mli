open! Base

(** Infrastructure failure shared by repository ports. Details of unexpected
    failures remain available for application logging but must not be exposed
    directly in HTTP responses. *)
type t =
  [ `Unavailable
  | `Unexpected of string
  ]

(** Returns a sanitized message suitable for a public response. *)
val public_message : t -> string
