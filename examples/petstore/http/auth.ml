open! Base

type t =
  { bearer_token : string
  ; api_key : string
  }

let getenv_or_default name default = Stdlib.Sys.getenv_opt name |> Option.value ~default

let from_env () =
  { bearer_token = getenv_or_default "PETSTORE_BEARER_TOKEN" "demo-token"
  ; api_key = getenv_or_default "PETSTORE_API_KEY" "demo-key"
  }
;;
