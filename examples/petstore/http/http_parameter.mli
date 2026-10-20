(** Scalar HTTP codecs shared by Petstore routes. Parsing rules and schemas
    express transport constraints; controllers pass the resulting typed values
    to domain-oriented application services. *)

open! Base
open Typed_endpoint

(** Positive pet identifier within the OCaml integer range. *)
module Pet_id : Parameter.S with type t = int

(** Positive order identifier. *)
module Order_id : Parameter.S with type t = int

(** Non-empty username. *)
module Username : Parameter.S with type t = string

(** Non-empty clear-text password used only by the demo login route. *)
module Password : Parameter.S with type t = string

(** Non-empty name used by the partial-update route. *)
module Pet_name : Parameter.S with type t = string

(** Bounded one-based page number. *)
module Page : Parameter.S with type t = int

(** Bounded page size. *)
module Limit : Parameter.S with type t = int
