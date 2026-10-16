open! Base

module Documentation = struct
  type t =
    { description : string
    ; tags : string list
    }

  let v ?(tags = []) ~description () = { description; tags }
end

module Operation_metadata = struct
  type t =
    { description : string
    ; summary : string option
    ; tags : string list
    ; deprecated : bool
    ; operation_id : string option
    }

  let v ?summary ?(tags = []) ?(deprecated = false) ?operation_id ~description () =
    { description; summary; tags; deprecated; operation_id }
  ;;
end

module Schema = struct
  type t =
    { value : Json_schema.packed
    ; name : string option
    }

  let v ?name value = { value = Json_schema.pack value; name }

  let equal left right =
    Option.equal String.equal left.name right.name
    && Json_schema.equal_packed left.value right.value
  ;;
end

module Security = struct
  module Scheme = struct
    type api_key_location =
      [ `Header
      | `Query
      | `Cookie
      ]

    type kind =
      | Api_key of
          { parameter : string
          ; location : api_key_location
          }
      | Http_bearer of { bearer_format : string option }
      | Oauth2_implicit of
          { authorization_url : string
          ; scopes : (string * string) list
          }

    type t =
      { name : string
      ; description : string
      ; kind : kind
      }

    let api_key ~name ~parameter ~location ~description () =
      { name; description; kind = Api_key { parameter; location } }
    ;;

    let http_bearer ~name ?bearer_format ~description () =
      { name; description; kind = Http_bearer { bearer_format } }
    ;;

    let oauth2_implicit ~name ~authorization_url ~scopes ~description () =
      { name; description; kind = Oauth2_implicit { authorization_url; scopes } }
    ;;

    let equal left right = Poly.equal left right
  end

  type requirement = (Scheme.t * string list) list

  let require ?(scopes = []) scheme = [ scheme, scopes ]

  let all requirements =
    List.concat requirements
    |> List.fold ~init:[] ~f:(fun combined (scheme, scopes) ->
      match
        List.findi combined ~f:(fun _ (existing, _scopes) ->
          String.equal existing.Scheme.name scheme.Scheme.name
          && Scheme.equal existing scheme)
      with
      | None -> combined @ [ scheme, List.dedup_and_sort scopes ~compare:String.compare ]
      | Some (index, (existing, existing_scopes)) ->
        let merged_scopes =
          List.dedup_and_sort (existing_scopes @ scopes) ~compare:String.compare
        in
        List.mapi combined ~f:(fun current item ->
          if Int.equal current index then
            existing, merged_scopes
          else
            item))
  ;;

  let combine_alternatives left right =
    match left, right with
    | [], alternatives | alternatives, [] -> alternatives
    | left, right ->
      List.concat_map left ~f:(fun left_requirement ->
        List.map right ~f:(fun right_requirement ->
          all [ left_requirement; right_requirement ]))
  ;;
end

module Openapi = struct
  module Server = struct
    type t =
      { url : string
      ; description : string option
      }

    let v ~url ?description () = { url; description }
  end

  module Config = struct
    type t =
      { title : string
      ; version : string
      ; description : string option
      ; servers : Server.t list
      }

    let v ~title ~version ?description ?(servers = []) () =
      { title; version; description; servers }
    ;;

    let default = v ~title:"API" ~version:"0.1.0" ()
  end
end

type param_kind =
  [ `Path
  | `Query
  | `Header
  ]

type query_encoding =
  [ `Csv
  | `Repeated
  ]

type param =
  { name : string
  ; kind : param_kind
  ; required : bool
  ; schema : Schema.t
  ; query_encoding : query_encoding option
  ; metadata : Documentation.t
  }

type request_body =
  | No_body
  | Json_body of
      { schema : Schema.t
      ; metadata : Documentation.t
      ; max_body_bytes : int
      ; media_types : string list
      }
  | Text_body of
      { metadata : Documentation.t
      ; max_body_bytes : int
      }
  | Binary_body of
      { metadata : Documentation.t
      ; max_body_bytes : int
      }

type response_content =
  | Text
  | Json of Schema.t list

type response_header =
  { name : string
  ; required : bool
  ; schema : Schema.t
  ; metadata : Documentation.t
  }

type response_payload =
  { metadata : Documentation.t
  ; content : response_content list
  ; headers : response_header list
  }

type response =
  { status : int
  ; payload : response_payload
  }

type endpoint =
  { meth : string
  ; path : string
  ; metadata : Operation_metadata.t option
  ; params : param list
  ; request_body : request_body
  ; responses : response list
  ; decode_error_responses : response list
  ; context_responses : response list
  ; security : Security.requirement list
  }

type route =
  { meth : string
  ; path : string
  ; endpoint : endpoint option
  }

type group =
  { prefix : string list
  ; metadata : Operation_metadata.t
  ; routes : route list
  }

module Compile_error = struct
  type t =
    | Duplicate_route of
        { meth : string
        ; path : string
        }
    | Ambiguous_route of
        { meth : string
        ; path : string
        ; conflicts_with : string
        }
    | Invalid_group_prefix_segment of string
    | Invalid_route_path of
        { meth : string
        ; path : string
        }
    | Invalid_openapi_method of
        { meth : string
        ; path : string
        }
    | Mismatched_path_parameters of
        { meth : string
        ; path : string
        ; declared : string list
        ; captures : string list
        }
    | Duplicate_operation_id of string
    | Duplicate_parameter of
        { meth : string
        ; path : string
        ; kind : param_kind
        ; name : string
        }
    | Array_query_requires_codec of
        { meth : string
        ; path : string
        ; name : string
        }
    | Duplicate_response_status of
        { meth : string
        ; path : string
        ; status : int
        }
    | Invalid_response_status of
        { meth : string
        ; path : string
        ; status : int
        }
    | Invalid_no_content_response of
        { meth : string
        ; path : string
        ; status : int
        }
    | Invalid_body_limit of
        { meth : string
        ; path : string
        ; max_body_bytes : int
        }
    | Invalid_json_media_types of
        { meth : string
        ; path : string
        ; media_types : string list
        }
    | Reserved_request_header of
        { meth : string
        ; path : string
        ; name : string
        }
    | Invalid_header_name of
        { meth : string
        ; path : string
        ; name : string
        }
    | Reserved_response_header of
        { meth : string
        ; path : string
        ; status : int
        ; name : string
        }
    | Duplicate_response_header of
        { meth : string
        ; path : string
        ; status : int
        ; name : string
        }
    | Conflicting_response_header of
        { meth : string
        ; path : string
        ; status : int
        ; name : string
        }
    | Invalid_schema_name of string
    | Conflicting_schema of string
    | Invalid_security_scheme_name of string
    | Conflicting_security_scheme of string
    | Invalid_security_scope of
        { scheme : string
        ; scope : string
        }
    | Invalid_security_scheme_parameter of
        { scheme : string
        ; parameter : string
        }
    | Invalid_security_authorization_url of string
    | Duplicate_oauth_scope of
        { scheme : string
        ; scope : string
        }

  let to_string = function
    | Duplicate_route { meth; path } -> "duplicate route: " ^ meth ^ " " ^ path
    | Ambiguous_route { meth; path; conflicts_with } ->
      "ambiguous route: " ^ meth ^ " " ^ path ^ " conflicts with " ^ conflicts_with
    | Invalid_group_prefix_segment segment -> "invalid group prefix segment: " ^ segment
    | Invalid_route_path { meth; path } ->
      "invalid typed route path: " ^ meth ^ " " ^ path
    | Invalid_openapi_method { meth; path } ->
      "HTTP method is not supported by OpenAPI: " ^ meth ^ " " ^ path
    | Mismatched_path_parameters { meth; path; declared; captures } ->
      let names values = "[" ^ String.concat values ~sep:", " ^ "]" in
      "path captures do not match declared parameters: "
      ^ meth
      ^ " "
      ^ path
      ^ "; declared "
      ^ names declared
      ^ ", captures "
      ^ names captures
    | Duplicate_operation_id operation_id -> "duplicate operationId: " ^ operation_id
    | Duplicate_parameter { meth; path; kind; name } ->
      let source =
        match kind with
        | `Path -> "path"
        | `Query -> "query"
        | `Header -> "header"
      in
      "duplicate " ^ source ^ " parameter " ^ name ^ ": " ^ meth ^ " " ^ path
    | Duplicate_response_status { meth; path; status } ->
      "duplicate response status " ^ Int.to_string status ^ ": " ^ meth ^ " " ^ path
    | Invalid_response_status { meth; path; status } ->
      "invalid response status " ^ Int.to_string status ^ ": " ^ meth ^ " " ^ path
    | Invalid_no_content_response { meth; path; status } ->
      "response status "
      ^ Int.to_string status
      ^ " must use an empty payload: "
      ^ meth
      ^ " "
      ^ path
    | Invalid_body_limit { meth; path; max_body_bytes } ->
      "invalid body limit " ^ Int.to_string max_body_bytes ^ ": " ^ meth ^ " " ^ path
    | Invalid_json_media_types { meth; path; media_types } ->
      "invalid JSON media types "
      ^ String.concat ~sep:", " media_types
      ^ ": "
      ^ meth
      ^ " "
      ^ path
    | Reserved_request_header { meth; path; name } ->
      "request header " ^ name ^ " is reserved: " ^ meth ^ " " ^ path
    | Invalid_header_name { meth; path; name } ->
      "invalid header name " ^ name ^ ": " ^ meth ^ " " ^ path
    | Reserved_response_header { meth; path; status; name } ->
      "response header "
      ^ name
      ^ " is reserved for status "
      ^ Int.to_string status
      ^ ": "
      ^ meth
      ^ " "
      ^ path
    | Duplicate_response_header { meth; path; status; name } ->
      "duplicate response header "
      ^ name
      ^ " for status "
      ^ Int.to_string status
      ^ ": "
      ^ meth
      ^ " "
      ^ path
    | Conflicting_response_header { meth; path; status; name } ->
      "conflicting response header "
      ^ name
      ^ " for status "
      ^ Int.to_string status
      ^ ": "
      ^ meth
      ^ " "
      ^ path
    | Array_query_requires_codec { meth; path; name } ->
      "array query parameter " ^ name ^ " requires a Query codec: " ^ meth ^ " " ^ path
    | Invalid_schema_name name -> "invalid OpenAPI schema name: " ^ name
    | Conflicting_schema name -> "conflicting OpenAPI schema: " ^ name
    | Invalid_security_scheme_name name -> "invalid security scheme name: " ^ name
    | Conflicting_security_scheme name -> "conflicting security scheme: " ^ name
    | Invalid_security_scope { scheme; scope } ->
      "invalid security scope " ^ scope ^ " for scheme " ^ scheme
    | Invalid_security_scheme_parameter { scheme; parameter } ->
      "invalid API-key header name " ^ parameter ^ " for security scheme " ^ scheme
    | Invalid_security_authorization_url scheme ->
      "invalid OAuth authorization URL for security scheme " ^ scheme
    | Duplicate_oauth_scope { scheme; scope } ->
      "duplicate OAuth scope " ^ scope ^ " for security scheme " ^ scheme
  ;;
end

module Compiled = struct
  type compiled_route =
    { meth : string
    ; path : string
    ; endpoint : endpoint option
    }

  type compiled_group =
    { metadata : Operation_metadata.t
    ; routes : compiled_route list
    }

  type t =
    { groups : compiled_group list
    ; schemas : Schema.t list
    ; security_schemes : Security.Scheme.t list
    }

  let groups t = t.groups
  let schemas t = t.schemas
  let security_schemes t = t.security_schemes
end

let prefix_to_string = function
  | [] -> ""
  | segments -> "/" ^ String.concat ~sep:"/" segments
;;

let full_path ~prefix path =
  if String.is_empty prefix then
    path
  else if String.equal path "/" then
    prefix
  else
    prefix ^ path
;;

let valid_static_segment segment =
  let is_hex = function
    | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true
    | _ -> false
  in
  let rec loop index =
    if index = String.length segment then
      true
    else (
      match
        segment.[index]
      with
      | '%' ->
        index + 2 < String.length segment
        && is_hex segment.[index + 1]
        && is_hex segment.[index + 2]
        && loop (index + 3)
      | '?' | '#' | '/' -> false
      | c -> Char.to_int c > 32 && Char.to_int c <> 127 && loop (index + 1))
  in
  (not (String.is_empty segment))
  && (not (String.equal segment "."))
  && (not (String.equal segment ".."))
  && loop 0
;;

let valid_capture_name name =
  String.split name ~on:'.'
  |> List.for_all ~f:(fun part ->
    (not (String.is_empty part))
    && String.for_all part ~f:(function
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
      | _ -> false))
;;

let valid_group_prefix_segment segment =
  valid_static_segment segment
  && (not (String.is_prefix segment ~prefix:":"))
  && not (String.is_prefix segment ~prefix:"*")
;;

let valid_typed_route_path path =
  String.equal path "/"
  || (String.is_prefix path ~prefix:"/"
      && String.drop_prefix path 1
         |> String.split ~on:'/'
         |> List.for_all ~f:(fun segment ->
           match String.chop_prefix segment ~prefix:":" with
           | Some name -> valid_capture_name name
           | None ->
             valid_static_segment segment && not (String.is_prefix segment ~prefix:"*")))
;;

let path_to_template path =
  String.split path ~on:'/'
  |> List.map ~f:(fun segment ->
    match String.chop_prefix segment ~prefix:":" with
    | Some name -> "{" ^ name ^ "}"
    | None ->
      String.concat_map segment ~f:(function
        | '{' -> "%7B"
        | '}' -> "%7D"
        | c -> String.of_char c))
  |> String.concat ~sep:"/"
;;

let path_captures path =
  String.split path ~on:'/'
  |> List.filter_map ~f:(fun segment -> String.chop_prefix segment ~prefix:":")
;;

let duplicate_statuses statuses =
  let seen = Hash_set.create (module Int) in
  List.filter statuses ~f:(fun status ->
    if Hash_set.mem seen status then
      true
    else (
      Hash_set.add seen status;
      false))
;;

let duplicate_parameters params =
  let seen = Hash_set.create (module String) in
  List.filter params ~f:(fun param ->
    let kind, name =
      match param.kind with
      | `Path -> "path", param.name
      | `Query -> "query", param.name
      | `Header -> "header", String.lowercase param.name
    in
    let key = kind ^ "\000" ^ name in
    if Hash_set.mem seen key then
      true
    else (
      Hash_set.add seen key;
      false))
;;

let route_shape path =
  String.split path ~on:'/'
  |> List.map ~f:(fun segment ->
    if String.is_prefix segment ~prefix:":" then
      ":"
    else
      segment)
  |> String.concat ~sep:"/"
;;

let valid_json_media_type value =
  let token s =
    (not (String.is_empty s))
    && String.for_all s ~f:(function
      | 'a' .. 'z'
      | '0' .. '9'
      | '!' | '#' | '$' | '%' | '&' | '\'' | '^' | '_' | '.' | '+' | '-' | '`' | '|' | '~'
        -> true
      | _ -> false)
  in
  String.equal value "application/json"
  ||
  match String.chop_prefix value ~prefix:"application/" with
  | None -> false
  | Some subtype ->
    String.is_suffix subtype ~suffix:"+json" && String.length subtype > 5 && token subtype
;;

let valid_http_status status = status >= 200 && status <= 599

let status_forbids_content status =
  (status >= 100 && status < 200) || status = 204 || status = 205 || status = 304
;;

let valid_openapi_method meth =
  List.mem
    [ "get"; "put"; "post"; "delete"; "options"; "head"; "patch"; "trace" ]
    meth
    ~equal:String.equal
;;

let valid_header_name name =
  (not (String.is_empty name))
  && String.for_all name ~f:(fun char ->
    Char.is_alphanum char || String.mem "!#$%&'*+-.^_`|~" char)
;;

let uri_unreserved char = Char.is_alphanum char || String.mem "-._~" char
let uri_sub_delimiter char = String.mem "!$&'()*+,;=" char

let valid_uri_component value ~allowed =
  let rec loop index =
    if index = String.length value then
      true
    else if Char.equal value.[index] '%' then
      index + 2 < String.length value
      && Char.is_hex_digit value.[index + 1]
      && Char.is_hex_digit value.[index + 2]
      && loop (index + 3)
    else
      allowed value.[index] && loop (index + 1)
  in
  loop 0
;;

let valid_ipv4_literal value =
  let octets = String.split value ~on:'.' in
  List.length octets = 4
  && List.for_all octets ~f:(fun octet ->
    let length = String.length octet in
    length > 0
    && length <= 3
    && (length = 1 || not (Char.equal octet.[0] '0'))
    && String.for_all octet ~f:Char.is_digit
    && Option.value_map (Int.of_string_opt octet) ~default:false ~f:(fun number ->
      number <= 255))
;;

let valid_ipv6_literal value =
  let groups value =
    if String.is_empty value then
      []
    else
      String.split value ~on:':'
  in
  let compressed, parts =
    match String.substr_index value ~pattern:"::" with
    | None -> false, groups value
    | Some index ->
      let left = String.prefix value index in
      let right = String.drop_prefix value (index + 2) in
      true, groups left @ groups right
  in
  let weights =
    List.mapi parts ~f:(fun index part ->
      if String.mem part '.' then
        if
          index = List.length parts - 1
          && String.is_suffix value ~suffix:part
          && valid_ipv4_literal part
        then
          Some 2
        else
          None
      else if
        (not (String.is_empty part))
        && String.length part <= 4
        && String.for_all part ~f:Char.is_hex_digit
      then
        Some 1
      else
        None)
  in
  List.for_all weights ~f:Option.is_some
  &&
  let count =
    List.fold weights ~init:0 ~f:(fun total weight ->
      total + Option.value weight ~default:0)
  in
  if compressed then
    count < 8
  else
    count = 8
;;

let valid_ip_literal value =
  match String.chop_prefix value ~prefix:"v" with
  | None -> valid_ipv6_literal value
  | Some future ->
    (match String.lsplit2 future ~on:'.' with
     | None -> false
     | Some (version, address) ->
       (not (String.is_empty version))
       && String.for_all version ~f:Char.is_hex_digit
       && (not (String.is_empty address))
       && String.for_all address ~f:(fun char ->
         uri_unreserved char || uri_sub_delimiter char || Char.equal char ':'))
;;

let valid_authorization_url value =
  let value = String.lowercase value in
  let remainder =
    match String.chop_prefix value ~prefix:"https://" with
    | Some remainder -> Some remainder
    | None -> String.chop_prefix value ~prefix:"http://"
  in
  let pchar char =
    uri_unreserved char || uri_sub_delimiter char || String.mem ":@" char
  in
  let valid_port value = String.for_all value ~f:Char.is_digit in
  let valid_host_port value =
    if String.is_prefix value ~prefix:"[" then (
      match
        String.lsplit2 (String.drop_prefix value 1) ~on:']'
      with
      | None -> false
      | Some (literal, suffix) ->
        valid_ip_literal literal
        && (String.is_empty suffix
            || Option.value_map
                 (String.chop_prefix suffix ~prefix:":")
                 ~default:false
                 ~f:valid_port))
    else (
      let valid_name name =
        (not (String.is_empty name))
        && valid_uri_component name ~allowed:(fun char ->
          uri_unreserved char || uri_sub_delimiter char)
      in
      match String.split value ~on:':' with
      | [ name ] -> valid_name name
      | [ name; port ] -> valid_name name && valid_port port
      | _ -> false)
  in
  match remainder with
  | None -> false
  | Some remainder ->
    let authority_path, query =
      match String.lsplit2 remainder ~on:'?' with
      | None -> remainder, ""
      | Some (authority_path, query) -> authority_path, query
    in
    let authority, path =
      match String.lsplit2 authority_path ~on:'/' with
      | None -> authority_path, ""
      | Some (authority, path) -> authority, path
    in
    let valid_authority =
      match String.split authority ~on:'@' with
      | [ host ] -> valid_host_port host
      | [ userinfo; host ] ->
        valid_uri_component userinfo ~allowed:(fun char ->
          uri_unreserved char || uri_sub_delimiter char || Char.equal char ':')
        && valid_host_port host
      | _ -> false
    in
    valid_authority
    && valid_uri_component path ~allowed:(fun char -> pchar char || Char.equal char '/')
    && valid_uri_component query ~allowed:(fun char -> pchar char || String.mem "/?" char)
;;

let response_header_equal left right =
  String.Caseless.equal left.name right.name
  && Bool.equal left.required right.required
  && Schema.equal left.schema right.schema
  && Poly.equal left.metadata right.metadata
;;

let duplicate_response_headers headers =
  let seen = Hash_set.create (module String) in
  List.filter headers ~f:(fun header ->
    let name = String.lowercase header.name in
    if Hash_set.mem seen name then
      true
    else (
      Hash_set.add seen name;
      false))
;;

let deduplicate_schemas schemas =
  List.fold schemas ~init:[] ~f:(fun unique schema ->
    if List.exists unique ~f:(Schema.equal schema) then
      unique
    else
      unique @ [ schema ])
;;

let merge_payloads primary secondary =
  let contents = primary.content @ secondary.content in
  let has_text =
    List.exists contents ~f:(function
      | Text -> true
      | Json _ -> false)
  in
  let schemas =
    List.concat_map contents ~f:(function
      | Text -> []
      | Json schemas -> schemas)
    |> deduplicate_schemas
  in
  let json_content =
    if List.is_empty schemas then
      []
    else
      [ Json schemas ]
  in
  let headers =
    List.fold secondary.headers ~init:primary.headers ~f:(fun headers header ->
      if List.exists headers ~f:(fun existing -> response_header_equal existing header)
      then
        headers
      else
        headers @ [ header ])
  in
  { primary with
    headers
  ; content =
      (if has_text then
         [ Text ]
       else
         [])
      @ json_content
  }
;;

let add_response responses additional =
  if
    List.exists responses ~f:(fun response -> Int.equal response.status additional.status)
  then
    List.map responses ~f:(fun response ->
      if Int.equal response.status additional.status then
        { response with payload = merge_payloads response.payload additional.payload }
      else
        response)
  else
    responses @ [ additional ]
;;

let add_implicit_responses (endpoint : endpoint) =
  let responses =
    List.fold
      (endpoint.decode_error_responses @ endpoint.context_responses)
      ~init:endpoint.responses
      ~f:add_response
  in
  { endpoint with responses; decode_error_responses = []; context_responses = [] }
;;

let valid_component_name name =
  (not (String.is_empty name))
  && String.for_all name ~f:(fun char ->
    Char.is_alphanum char
    || Char.equal char '.'
    || Char.equal char '_'
    || Char.equal char '-')
;;

let schemas_of_endpoint (endpoint : endpoint) =
  let params = List.map endpoint.params ~f:(fun param -> param.schema) in
  let request =
    match endpoint.request_body with
    | No_body | Text_body _ | Binary_body _ -> []
    | Json_body { schema; _ } -> [ schema ]
  in
  let responses =
    List.concat_map endpoint.responses ~f:(fun response ->
      List.map response.payload.headers ~f:(fun header -> header.schema)
      @ List.concat_map response.payload.content ~f:(function
        | Text -> []
        | Json schemas -> schemas))
  in
  params @ request @ responses
;;

let body_limit = function
  | No_body -> None
  | Json_body { max_body_bytes; _ }
  | Text_body { max_body_bytes; _ }
  | Binary_body { max_body_bytes; _ } -> Some max_body_bytes
;;

let validate_security_scope scheme scope =
  match scheme.Security.Scheme.kind with
  | Oauth2_implicit { scopes; _ } ->
    List.exists scopes ~f:(fun (declared, _description) -> String.equal declared scope)
  | Api_key _ | Http_bearer _ -> false
;;

let array_schema schema =
  match Json_schema.to_yojson_packed schema.Schema.value with
  | `Assoc fields ->
    (match List.Assoc.find fields "type" ~equal:String.equal with
     | Some (`String "array") -> true
     | Some (`List types) -> List.mem types (`String "array") ~equal:Yojson.Safe.equal
     | _ -> false)
  | _ -> false
;;

let compile (groups : group list) : (Compiled.t, Compile_error.t list) Result.t =
  let routes_seen = Hashtbl.create (module String) in
  let operation_ids = Hash_set.create (module String) in
  let named_schemas = Hashtbl.create (module String) in
  let security_schemes = Hashtbl.create (module String) in
  let errors = ref [] in
  let add_error error = errors := error :: !errors in
  let register_schema schema =
    Option.iter schema.Schema.name ~f:(fun name ->
      if not (valid_component_name name) then
        add_error (Compile_error.Invalid_schema_name name)
      else (
        match
          Hashtbl.find named_schemas name
        with
        | None -> Hashtbl.set named_schemas ~key:name ~data:schema
        | Some existing ->
          if not (Schema.equal existing schema) then
            add_error (Compile_error.Conflicting_schema name)))
  in
  let register_scheme scheme =
    let name = scheme.Security.Scheme.name in
    if not (valid_component_name name) then
      add_error (Compile_error.Invalid_security_scheme_name name)
    else (
      match
        Hashtbl.find security_schemes name
      with
      | None ->
        Hashtbl.set security_schemes ~key:name ~data:scheme;
        (match scheme.Security.Scheme.kind with
         | Api_key { parameter; location = `Header }
           when not (valid_header_name parameter) ->
           add_error
             (Compile_error.Invalid_security_scheme_parameter { scheme = name; parameter })
         | Oauth2_implicit { authorization_url; scopes } ->
           if not (valid_authorization_url authorization_url) then
             add_error (Compile_error.Invalid_security_authorization_url name);
           let seen = Hash_set.create (module String) in
           List.iter scopes ~f:(fun (scope, _description) ->
             if Hash_set.mem seen scope then
               add_error (Compile_error.Duplicate_oauth_scope { scheme = name; scope })
             else
               Hash_set.add seen scope)
         | Api_key _ | Http_bearer _ -> ())
      | Some existing ->
        if not (Security.Scheme.equal existing scheme) then
          add_error (Compile_error.Conflicting_security_scheme name))
  in
  let compiled_groups =
    List.map groups ~f:(fun group ->
      let prefix_is_valid = List.for_all group.prefix ~f:valid_group_prefix_segment in
      List.filter group.prefix ~f:(Fn.non valid_group_prefix_segment)
      |> List.iter ~f:(fun segment ->
        add_error (Compile_error.Invalid_group_prefix_segment segment));
      let prefix = prefix_to_string group.prefix in
      let routes =
        List.map group.routes ~f:(fun route ->
          let path = full_path ~prefix route.path in
          let route_key = route.meth ^ " " ^ route_shape path in
          (match Hashtbl.find routes_seen route_key with
           | None -> Hashtbl.set routes_seen ~key:route_key ~data:path
           | Some first_path when String.equal first_path path ->
             add_error (Compile_error.Duplicate_route { meth = route.meth; path })
           | Some conflicts_with ->
             add_error
               (Compile_error.Ambiguous_route { meth = route.meth; path; conflicts_with }));
          let endpoint =
            Option.map route.endpoint ~f:(fun endpoint ->
              let route_path_is_valid = valid_typed_route_path route.path in
              if not route_path_is_valid then
                add_error (Compile_error.Invalid_route_path { meth = route.meth; path });
              if not (valid_openapi_method route.meth) then
                add_error
                  (Compile_error.Invalid_openapi_method { meth = route.meth; path });
              if prefix_is_valid && route_path_is_valid then (
                let declared =
                  List.filter_map endpoint.params ~f:(fun parameter ->
                    match parameter.kind with
                    | `Path -> Some parameter.name
                    | `Query | `Header -> None)
                in
                let captures = path_captures path in
                if not (List.equal String.equal declared captures) then
                  add_error
                    (Compile_error.Mismatched_path_parameters
                       { meth = route.meth; path; declared; captures }));
              Option.iter endpoint.metadata ~f:(fun metadata ->
                Option.iter metadata.operation_id ~f:(fun operation_id ->
                  if Hash_set.mem operation_ids operation_id then
                    add_error (Compile_error.Duplicate_operation_id operation_id)
                  else
                    Hash_set.add operation_ids operation_id));
              Option.iter (body_limit endpoint.request_body) ~f:(fun max_body_bytes ->
                if max_body_bytes <= 0 then
                  add_error
                    (Compile_error.Invalid_body_limit
                       { meth = route.meth; path; max_body_bytes }));
              (match endpoint.request_body with
               | Json_body { media_types; _ }
                 when List.is_empty media_types
                      || not (List.for_all media_types ~f:valid_json_media_type) ->
                 add_error
                   (Compile_error.Invalid_json_media_types
                      { meth = route.meth; path; media_types })
               | _ -> ());
              let statuses =
                List.map endpoint.responses ~f:(fun response -> response.status)
              in
              duplicate_parameters endpoint.params
              |> List.iter ~f:(fun parameter ->
                add_error
                  (Compile_error.Duplicate_parameter
                     { meth = route.meth
                     ; path
                     ; kind = parameter.kind
                     ; name = parameter.name
                     }));
              List.iter endpoint.params ~f:(fun parameter ->
                match parameter.kind with
                | `Header when not (valid_header_name parameter.name) ->
                  add_error
                    (Compile_error.Invalid_header_name
                       { meth = route.meth; path; name = parameter.name })
                | `Header
                  when List.exists
                         [ "accept"; "content-type"; "authorization" ]
                         ~f:(String.Caseless.equal parameter.name) ->
                  add_error
                    (Compile_error.Reserved_request_header
                       { meth = route.meth; path; name = parameter.name })
                | `Query
                  when Option.is_none parameter.query_encoding
                       && array_schema parameter.schema ->
                  add_error
                    (Compile_error.Array_query_requires_codec
                       { meth = route.meth; path; name = parameter.name })
                | `Path | `Query | `Header -> ());
              let declared_responses =
                endpoint.responses @ endpoint.decode_error_responses
                @ endpoint.context_responses
              in
              let duplicate_response_header_keys = Hash_set.create (module String) in
              List.iter declared_responses ~f:(fun response ->
                List.iter response.payload.headers ~f:(fun header ->
                  if not (valid_header_name header.name) then
                    add_error
                      (Compile_error.Invalid_header_name
                         { meth = route.meth; path; name = header.name });
                  if
                    List.exists
                      [ "content-type"
                      ; "content-length"
                      ; "transfer-encoding"
                      ; "trailer"
                      ; "connection"
                      ]
                      ~f:(String.Caseless.equal header.name)
                  then
                    add_error
                      (Compile_error.Reserved_response_header
                         { meth = route.meth
                         ; path
                         ; status = response.status
                         ; name = header.name
                         }));
                duplicate_response_headers response.payload.headers
                |> List.iter ~f:(fun header ->
                  Hash_set.add
                    duplicate_response_header_keys
                    (Int.to_string response.status ^ "\000" ^ String.lowercase header.name);
                  add_error
                    (Compile_error.Duplicate_response_header
                       { meth = route.meth
                       ; path
                       ; status = response.status
                       ; name = header.name
                       })));
              List.iter endpoint.responses ~f:(fun response ->
                if not (valid_http_status response.status) then
                  add_error
                    (Compile_error.Invalid_response_status
                       { meth = route.meth; path; status = response.status });
                match
                  status_forbids_content response.status, response.payload.content
                with
                | false, _ | true, [] -> ()
                | true, _ :: _ ->
                  add_error
                    (Compile_error.Invalid_no_content_response
                       { meth = route.meth; path; status = response.status }));
              duplicate_statuses statuses
              |> List.iter ~f:(fun status ->
                add_error
                  (Compile_error.Duplicate_response_status
                     { meth = route.meth; path; status }));
              let endpoint = add_implicit_responses endpoint in
              List.iter endpoint.responses ~f:(fun response ->
                duplicate_response_headers response.payload.headers
                |> List.iter ~f:(fun header ->
                  let key =
                    Int.to_string response.status ^ "\000" ^ String.lowercase header.name
                  in
                  if not (Hash_set.mem duplicate_response_header_keys key) then
                    add_error
                      (Compile_error.Conflicting_response_header
                         { meth = route.meth
                         ; path
                         ; status = response.status
                         ; name = header.name
                         })));
              List.iter (schemas_of_endpoint endpoint) ~f:register_schema;
              List.iter endpoint.security ~f:(fun requirement ->
                List.iter requirement ~f:(fun (scheme, scopes) ->
                  register_scheme scheme;
                  List.iter scopes ~f:(fun scope ->
                    if not (validate_security_scope scheme scope) then
                      add_error
                        (Compile_error.Invalid_security_scope
                           { scheme = scheme.name; scope }))));
              endpoint)
          in
          { Compiled.meth = route.meth; path; endpoint })
      in
      { Compiled.metadata = group.metadata; routes })
  in
  match List.rev !errors with
  | [] ->
    let schemas =
      Hashtbl.data named_schemas
      |> List.sort ~compare:(fun left right ->
        Option.compare String.compare left.Schema.name right.Schema.name)
    in
    let security_schemes =
      Hashtbl.data security_schemes
      |> List.sort ~compare:(fun left right ->
        String.compare left.Security.Scheme.name right.Security.Scheme.name)
    in
    Ok { Compiled.groups = compiled_groups; schemas; security_schemes }
  | errors -> Error errors
;;

let compile_exn groups =
  match compile groups with
  | Ok compiled -> compiled
  | Error errors ->
    errors |> List.map ~f:Compile_error.to_string |> String.concat ~sep:"; " |> failwith
;;
