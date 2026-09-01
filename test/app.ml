open! Base

let swagger_ui_html =
  {|
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>API Docs</title>
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
    <style>
      html, body { margin: 0; padding: 0; height: 100%; }
      #swagger-ui { height: 100%; }
    </style>
  </head>
  <body>
    <div id="swagger-ui"></div>

    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
    <script>
      window.onload = function () {
        window.ui = SwaggerUIBundle({
          url: "/openapi.json",
          dom_id: "#swagger-ui",
          presets: [
            SwaggerUIBundle.presets.apis,
            SwaggerUIStandalonePreset
          ],
          layout: "StandaloneLayout"
        });
      };
    </script>
  </body>
</html>
|}
;;

module App (A : sig
    val app : Opium.App.builder
    val openapi : Yojson.Safe.t
  end) =
struct
  let openapi_json = Yojson.Safe.pretty_to_string A.openapi

  let main () =
    let headers_json =
      Cohttp.Header.init_with "content-type" "application/json; charset=utf-8"
    in
    let headers_html =
      Cohttp.Header.init_with "content-type" "text/html; charset=utf-8"
    in
    Opium.App.start
      (Opium.App.empty
       |> A.app
       |> Opium.App.get "/openapi.json" (fun _req ->
         Opium.Std.respond' ?headers:(Some headers_json) (`String openapi_json))
       |> Opium.App.get "/" (fun _req ->
         Opium.Std.respond' ?headers:(Some headers_html) (`String swagger_ui_html)))
    |> Lwt_main.run
  ;;
end

module Test1 = App (Typed_endpoint_test.Routes)

let () = Test1.main ()
