open! Base

type t =
  { now : unit -> float
  ; write : string -> unit
  ; fresh_id : unit -> string
  }

type request =
  { logger : t
  ; started_at : float
  ; timestamp : string
  ; method_ : string
  ; path : string
  ; request_id : string
  }

let counter = Atomic.make 0

let default_fresh_id () =
  let count = Atomic.fetch_and_add counter 1 in
  let milliseconds = Int.of_float (Stdlib.floor (Unix.gettimeofday () *. 1000.)) in
  Stdlib.Printf.sprintf "%d-%d-%d" (Unix.getpid ()) milliseconds count
;;

let write_stderr line =
  let rec write offset =
    if offset < String.length line then (
      let written =
        Unix.write_substring Unix.stderr line offset (String.length line - offset)
      in
      if written > 0 then
        write (offset + written))
  in
  try write 0 with
  | _ -> ()
;;

let create
      ?(now = Unix.gettimeofday)
      ?(write = write_stderr)
      ?(fresh_id = default_fresh_id)
      ()
  =
  { now; write; fresh_id }
;;

let format_timestamp seconds =
  let time = Unix.gmtime seconds in
  let milliseconds =
    Int.of_float (Stdlib.floor ((seconds -. Stdlib.floor seconds) *. 1000.))
    |> Int.max 0
    |> Int.min 999
  in
  Stdlib.Printf.sprintf
    "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ"
    (time.tm_year + 1900)
    (time.tm_mon + 1)
    time.tm_mday
    time.tm_hour
    time.tm_min
    time.tm_sec
    milliseconds
;;

let is_valid_request_id value =
  let valid_character character =
    Char.is_alphanum character || List.mem [ '.'; '_'; '-' ] character ~equal:Char.equal
  in
  let length = String.length value in
  length >= 1 && length <= 128 && String.for_all value ~f:valid_character
;;

let path_of_target target =
  try
    match Uri.of_string target |> Uri.path with
    | "" -> "/"
    | path -> path
  with
  | _ -> "/"
;;

let start logger ~method_ ~target ~request_id =
  let started_at = logger.now () in
  let request_id =
    match request_id with
    | Some value when is_valid_request_id value -> value
    | Some _ | None -> logger.fresh_id ()
  in
  { logger
  ; started_at
  ; timestamp = format_timestamp started_at
  ; method_
  ; path = path_of_target target
  ; request_id
  }
;;

let request_id request = request.request_id

let duration_ms request =
  let duration = Stdlib.max 0. (request.logger.now () -. request.started_at) in
  duration *. 1_000.
;;

let write request fields =
  let event = `Assoc fields |> Yojson.Safe.to_string |> fun json -> json ^ "\n" in
  try request.logger.write event with
  | _ -> ()
;;

let base_fields request ~level =
  [ "timestamp", `String request.timestamp
  ; "level", `String level
  ; "event", `String "http_request"
  ; "request_id", `String request.request_id
  ; "method", `String request.method_
  ; "path", `String request.path
  ; "duration_ms", `Float (duration_ms request)
  ]
;;

let finish request ~status =
  write request (base_fields request ~level:"info" @ [ "status", `Int status ])
;;

let fail request exn =
  write
    request
    (base_fields request ~level:"error" @ [ "error", `String (Exn.to_string exn) ])
;;
