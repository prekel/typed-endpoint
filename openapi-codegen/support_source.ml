open! Base

let ml =
  {|type 'a presence = Absent | Present of 'a
type 'a codec = { decode : Yojson.Safe.t -> ('a, string) Result.t; encode : 'a -> Yojson.Safe.t }
let string = { decode = (function `String x -> Ok x | _ -> Error "expected string"); encode = (fun x -> `String x) }
let int64 = {
  decode = (function
    | `Int x -> Ok (Int64.of_int x)
    | `Intlit x -> (try Ok (Int64.of_string x) with _ -> Error "integer outside int64 range")
    | _ -> Error "expected integer");
  encode = (fun x -> `Intlit (Int64.to_string x)) }
let number = {
  decode = (fun json ->
    let value = match json with
      | `Int x -> Some (Float.of_int x)
      | `Intlit x -> (try Some (Float.of_string x) with _ -> None)
      | `Float x -> Some x | _ -> None in
    match value with Some x when Float.is_finite x -> Ok x | _ -> Error "expected finite number");
  encode = (fun x -> if Float.is_finite x then `Float x else invalid_arg "non-finite JSON number") }
let bool = { decode = (function `Bool x -> Ok x | _ -> Error "expected boolean"); encode = (fun x -> `Bool x) }
let null = { decode = (function `Null -> Ok () | _ -> Error "expected null"); encode = (fun () -> `Null) }
let any = { decode = (fun x -> Ok x); encode = Fn.id }
let nullable codec = {
  decode = (function `Null -> Ok None | value -> Result.map (codec.decode value) ~f:Option.some);
  encode = (function None -> `Null | Some x -> codec.encode x) }
let list codec = {
  decode = (function `List xs -> Result.all (List.map xs ~f:codec.decode) | _ -> Error "expected array");
  encode = (fun xs -> `List (List.map xs ~f:codec.encode)) }
let object_fields = function
  | `Assoc fields ->
    let keys = List.map fields ~f:fst in
    if List.contains_dup keys ~compare:String.compare then Error "duplicate object property" else Ok fields
  | _ -> Error "expected object"
let required fields name codec =
  match List.Assoc.find fields name ~equal:String.equal with
  | None -> Error (Stdlib.Printf.sprintf "missing property %s" name)
  | Some x -> Result.map_error (codec.decode x) ~f:(fun e -> Stdlib.Printf.sprintf "%s: %s" name e)
let optional fields name codec =
  match List.Assoc.find fields name ~equal:String.equal with
  | None -> Ok None
  | Some x -> Result.map (codec.decode x) ~f:Option.some
let presence fields name codec =
  match List.Assoc.find fields name ~equal:String.equal with
  | None -> Ok Absent
  | Some x -> Result.map (codec.decode x) ~f:(fun x -> Present x)
let extras fields known codec =
  List.filter fields ~f:(fun (key,_) -> not (List.mem known key ~equal:String.equal))
  |> List.map ~f:(fun (key,value) -> Result.map (codec.decode value) ~f:(fun value -> key,value))
  |> Result.all
let closed fields known =
  if List.exists fields ~f:(fun (key,_) -> not (List.mem known key ~equal:String.equal)) then Error "unknown object property" else Ok ()
let field name codec x = [name, codec.encode x]
let optional_field name codec = function None -> [] | Some x -> field name codec x
let presence_field name codec = function Absent -> [] | Present x -> field name codec x
let encode_extras known codec xs =
  let names = List.map xs ~f:fst in
  if List.contains_dup names ~compare:String.compare || List.exists names ~f:(fun k -> List.mem known k ~equal:String.equal) then
    invalid_arg "additional properties duplicate declared fields";
  List.map xs ~f:(fun (k,v) -> k, codec.encode v)
let scalar codec ~string raw =
  if string then codec.decode (`String raw)
  else try codec.decode (Yojson.Safe.from_string raw) with Yojson.Json_error _ -> Error "invalid scalar"
let scalar_to_string codec value =
  match codec.encode value with `String x -> x | json -> Yojson.Safe.to_string json
|}
;;

let mli =
  {|type 'a presence = Absent | Present of 'a
type 'a codec = { decode : Yojson.Safe.t -> ('a, string) Result.t; encode : 'a -> Yojson.Safe.t }
val string : string codec
val int64 : int64 codec
val number : float codec
val bool : bool codec
val null : unit codec
val any : Yojson.Safe.t codec
val nullable : 'a codec -> 'a option codec
val list : 'a codec -> 'a list codec
val object_fields : Yojson.Safe.t -> ((string * Yojson.Safe.t) list, string) Result.t
val required : (string * Yojson.Safe.t) list -> string -> 'a codec -> ('a,string) Result.t
val optional : (string * Yojson.Safe.t) list -> string -> 'a codec -> ('a option,string) Result.t
val presence : (string * Yojson.Safe.t) list -> string -> 'a codec -> ('a presence,string) Result.t
val extras : (string * Yojson.Safe.t) list -> string list -> 'a codec -> ((string * 'a) list,string) Result.t
val closed : (string * Yojson.Safe.t) list -> string list -> (unit,string) Result.t
val field : string -> 'a codec -> 'a -> (string * Yojson.Safe.t) list
val optional_field : string -> 'a codec -> 'a option -> (string * Yojson.Safe.t) list
val presence_field : string -> 'a codec -> 'a presence -> (string * Yojson.Safe.t) list
val encode_extras : string list -> 'a codec -> (string * 'a) list -> (string * Yojson.Safe.t) list
val scalar : 'a codec -> string:bool -> string -> ('a,string) Result.t
val scalar_to_string : 'a codec -> 'a -> string
|}
;;
