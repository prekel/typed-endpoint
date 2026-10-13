open! Base

let now = Unix.gettimeofday

let token () =
  try
    let channel = Stdlib.open_in_bin "/dev/urandom" in
    let bytes =
      Exn.protect
        ~f:(fun () -> Stdlib.really_input_string channel 32)
        ~finally:(fun () -> Stdlib.close_in_noerr channel)
    in
    Ok
      (String.concat_map bytes ~f:(fun c -> Stdlib.Printf.sprintf "%02x" (Char.to_int c)))
  with
  | exn -> Error (Exn.to_string exn)
;;
