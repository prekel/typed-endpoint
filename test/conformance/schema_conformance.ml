open! Base
open Typed_endpoint
module Check = Contract_test_support

module Declared = struct
  type t =
    { count : int [@key "wire"] [@jsonschema.minimum 0] [@jsonschema.maximum 100]
    ; nullable : string option
    ; optional : string option [@default None]
    ; label : string [@default "label"]
    ; timestamp : string [@jsonschema.format `Date_time]
    ; wide : int64 [@encoding `string]
    }
  [@@deriving yojson, jsonschema]
end

module Integers = struct
  type t = int list [@@deriving yojson]
end

let member = Yojson.Safe.Util.member
let json = Json_schema.to_yojson

let validates schema value =
  Result.is_ok (Check.validate ~document:(`Assoc []) ~schema value)
;;

let declared count =
  Declared.
    { count
    ; nullable = None
    ; optional = None
    ; label = "label"
    ; timestamp = "2026-10-16T00:00:00Z"
    ; wide = 9223372036854775807L
    }
;;

let () =
  let schema = json Declared.t_jsonschema in
  let property name = schema |> member "properties" |> member name in
  assert (Poly.equal (property "wire" |> member "minimum") (`Int 0));
  assert (Poly.equal (property "wire" |> member "maximum") (`Int 100));
  assert (Poly.equal (property "timestamp" |> member "format") (`String "date-time"));
  assert (Poly.equal (property "wide" |> member "type") (`String "string"));
  assert (
    Poly.equal
      (property "nullable" |> member "type")
      (`List [ `String "string"; `String "null" ]));
  assert (
    not
      (List.Assoc.mem
         (Yojson.Safe.Util.to_assoc (property "nullable"))
         "default"
         ~equal:String.equal));
  assert (
    List.Assoc.mem
      (Yojson.Safe.Util.to_assoc (property "optional"))
      "default"
      ~equal:String.equal);
  assert (Poly.equal (property "optional" |> member "default") `Null);
  assert (Poly.equal (property "label" |> member "default") (`String "label"));
  let required = member "required" schema |> Yojson.Safe.Util.to_list in
  assert (List.mem required (`String "nullable") ~equal:Yojson.Safe.equal);
  assert (not (List.mem required (`String "optional") ~equal:Yojson.Safe.equal));
  assert (Poly.equal (member "additionalProperties" schema) (`Bool false));
  (* Schema constraints do not add checks to the independently derived codec. *)
  let outside = Declared.to_yojson (declared (-1)) in
  assert (Result.is_ok (Declared.of_yojson outside));
  assert (not (validates schema outside))
;;

let constraints =
  QCheck2.Test.make
    ~name:"generation: declared integer bounds match acceptance boundaries"
    ~count:300
    QCheck2.Gen.(pair (int_range (-1000) 1000) (int_range 0 1000))
    (fun (minimum, width) ->
       let maximum = minimum + width in
       let schema = Json_schema.integer ~minimum ~maximum () |> json in
       Poly.equal (member "minimum" schema) (`Int minimum)
       && Poly.equal (member "maximum" schema) (`Int maximum)
       && validates schema (`Int minimum)
       && validates schema (`Int maximum)
       && (not (validates schema (`Int (minimum - 1))))
       && not (validates schema (`Int (maximum + 1))))
;;

let serialization =
  QCheck2.Test.make
    ~name:"serialization: constrained DTO values conform and round-trip"
    ~count:300
    QCheck2.Gen.(int_range 0 100)
    (fun count ->
       let value = declared count in
       let encoded = Declared.to_yojson value in
       validates (json Declared.t_jsonschema) encoded
       && Poly.equal (Declared.of_yojson encoded) (Ok value))
;;

let collections =
  let generator =
    let open QCheck2.Gen in
    let* minimum = int_range 0 5 in
    let* maximum = int_range minimum 10 in
    let* length = int_range minimum maximum in
    let+ values = list_size (return length) (int_range 0 100) in
    minimum, maximum, values
  in
  QCheck2.Test.make
    ~name:"serialization: bounded collections preserve item and length constraints"
    ~count:300
    generator
    (fun (min_items, max_items, values) ->
       let schema =
         Json_schema.list
           ~min_items
           ~max_items
           ~items:(Json_schema.integer ~minimum:0 ~maximum:100 ())
           ()
         |> json
       in
       let encoded = Integers.to_yojson values in
       Poly.equal (member "minItems" schema) (`Int min_items)
       && Poly.equal (member "maxItems" schema) (`Int max_items)
       && validates schema encoded
       && Poly.equal (Integers.of_yojson encoded) (Ok values)
       && (not
             (validates
                schema
                (Integers.to_yojson (List.init (max_items + 1) ~f:(Fn.const 1)))))
       && not (validates schema (`List [ `Int (-1) ])))
;;

let () = QCheck_base_runner.run_tests_main [ constraints; serialization; collections ]
