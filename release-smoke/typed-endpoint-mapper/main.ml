open! Base

module Source = struct
  type t =
    { name : string
    ; ignored : int
    }
end

module Target = struct
  type t = { name : string }
end

let map = [%mapper fun (source : Source.t) -> ({ name } : Target.t)]
let fallible = [%mapper_result fun (source : Source.t) -> ({ name } : Target.t)]

let () =
  let source : Source.t = { name = "smoke"; ignored = 0 } in
  assert (source.ignored = 0);
  assert (String.equal (map source).name "smoke");
  assert (Result.is_ok (fallible source))
;;
