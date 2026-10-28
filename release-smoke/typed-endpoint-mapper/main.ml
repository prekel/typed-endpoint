open! Base

module Source = struct
  type t =
    { name : string
    ; ignored : int
    }
end

module Input = struct
  type t = { name : string }
end

module Target = struct
  let validate name =
    if String.is_empty name then
      Error (Typed_endpoint_mapper.Mapping_error.make ~code:"empty" ~message:"required")
    else
      Ok name
  ;;

  type t = { name : string [@mapper.into.result validate] }
  [@@deriving
    mapper_from { source = [%type: Source.t] }
  , mapper_into { target = [%type: Input.t]; fallible = true }]
end

let map = [%mapper fun (source : Source.t) -> ({ name } : Target.t)]
let fallible = [%mapper_result fun (source : Source.t) -> ({ name } : Target.t)]

let () =
  let source : Source.t = { name = "smoke"; ignored = 0 } in
  assert (source.ignored = 0);
  assert (String.equal (map source).name "smoke");
  assert (Result.is_ok (fallible source));
  let dto = Target.of_domain source in
  assert (String.equal dto.name "smoke");
  (match Target.to_domain dto with
   | Error _ -> assert false
   | Ok (input : Input.t) -> assert (String.equal input.name "smoke"));
  assert (Result.is_error (Target.to_domain { name = "" }))
;;
