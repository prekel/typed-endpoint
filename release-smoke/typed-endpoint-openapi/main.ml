open! Base

let () =
  let input =
    Yojson.Safe.from_string
      {|{"openapi":"3.0.3","info":{"title":"Smoke","version":"1"},"paths":{"/health":{"get":{"responses":{"204":{"description":"Healthy"}}}}}}|}
  in
  match Typed_endpoint_openapi.generate input with
  | Ok files -> assert (List.length files = 8)
  | Error errors ->
    Stdlib.failwith
      (String.concat
         ~sep:"; "
         (List.map errors ~f:Typed_endpoint_openapi.Diagnostic.to_string))
;;
