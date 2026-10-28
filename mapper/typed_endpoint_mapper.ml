open! Base

module Mapping_error = struct
  type segment =
    | Field of string
    | Index of int

  type t =
    { path : segment list
    ; code : string
    ; message : string
    }

  let make ~code ~message = { path = []; code; message }
  let path t = t.path
  let code t = t.code
  let message t = t.message

  let at segment result =
    Result.map_error result ~f:(fun t -> { t with path = segment :: t.path })
  ;;

  let at_field field = at (Field field)
  let at_index index = at (Index index)

  let to_string t =
    let path =
      List.fold t.path ~init:"" ~f:(fun acc -> function
        | Field name ->
          if String.is_empty acc then
            name
          else
            acc ^ "." ^ name
        | Index index -> acc ^ "[" ^ Int.to_string index ^ "]")
    in
    (if String.is_empty path then
       ""
     else
       path ^ ": ")
    ^ t.code ^ ": " ^ t.message
  ;;
end

module Converter = struct
  type ('a, 'b) t = 'a -> ('b, Mapping_error.t) Result.t

  let of_total f value = Ok (f value)

  let option f = function
    | None -> Ok None
    | Some value -> Result.map (f value) ~f:Option.some
  ;;

  let list f values =
    let open Result.Let_syntax in
    let rec loop index acc = function
      | [] -> Ok (List.rev acc)
      | value :: rest ->
        let%bind value = Mapping_error.at_index index (f value) in
        loop (index + 1) (value :: acc) rest
    in
    loop 0 [] values
  ;;

  let array f values = Result.map (list f (Array.to_list values)) ~f:Array.of_list
end
