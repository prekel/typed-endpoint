open! Base

let index =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Petstore API documentation</title>
    <style>
      :root { color-scheme: light dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; }
      body { margin: 0; background: #0f172a; color: #e2e8f0; }
      main { width: min(960px, calc(100% - 40px)); margin: 0 auto; padding: 72px 0; }
      h1 { margin: 0 0 12px; font-size: clamp(2rem, 6vw, 4rem); }
      p { color: #94a3b8; line-height: 1.6; }
      .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; margin-top: 40px; }
      a { display: block; padding: 24px; border: 1px solid #334155; border-radius: 16px; color: inherit; text-decoration: none; background: #111c32; }
      a:hover { border-color: #38bdf8; transform: translateY(-2px); }
      h2 { margin: 0 0 8px; }
      code { color: #7dd3fc; }
    </style>
  </head>
  <body>
    <main>
      <h1>Petstore API</h1>
      <p>Five renderers, one generated <code>/openapi.json</code> contract.</p>
      <div class="grid">
        <a href="/docs/swagger"><h2>Swagger UI</h2><p>The familiar interactive reference.</p></a>
        <a href="/docs/scalar"><h2>Scalar</h2><p>A modern reference with an integrated API client.</p></a>
        <a href="/docs/rapidoc"><h2>RapiDoc</h2><p>A lightweight and configurable web component.</p></a>
        <a href="/docs/redoc"><h2>Redoc</h2><p>A readable three-panel API reference.</p></a>
        <a href="/docs/elements"><h2>Stoplight Elements</h2><p>Developer-portal style interactive documentation.</p></a>
      </div>
    </main>
  </body>
</html>
|}
;;

let swagger =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Swagger UI — Petstore</title>
    <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.32.14/swagger-ui.css">
    <style>html { box-sizing: border-box; overflow-y: scroll; } body { margin: 0; background: #fafafa; }</style>
  </head>
  <body>
    <div id="swagger-ui"></div>
    <script src="https://unpkg.com/swagger-ui-dist@5.32.14/swagger-ui-bundle.js" crossorigin="anonymous"></script>
    <script src="https://unpkg.com/swagger-ui-dist@5.32.14/swagger-ui-standalone-preset.js" crossorigin="anonymous"></script>
    <script>
      window.onload = function () {
        SwaggerUIBundle({
          url: "/openapi.json",
          dom_id: "#swagger-ui",
          deepLinking: true,
          persistAuthorization: true,
          presets: [SwaggerUIBundle.presets.apis, SwaggerUIStandalonePreset],
          layout: "StandaloneLayout"
        });
      };
    </script>
  </body>
</html>
|}
;;

let scalar =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Scalar — Petstore</title>
  </head>
  <body>
    <div id="app"></div>
    <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.67.0" crossorigin="anonymous"></script>
    <script>
      Scalar.createApiReference("#app", {
        url: "/openapi.json",
        theme: "default",
        telemetry: false,
        agent: { disabled: true }
      });
    </script>
  </body>
</html>
|}
;;

let rapidoc =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>RapiDoc — Petstore</title>
    <script type="module" src="https://unpkg.com/rapidoc@9.3.8/dist/rapidoc-min.js" crossorigin="anonymous"></script>
  </head>
  <body>
    <rapi-doc
      spec-url="/openapi.json"
      render-style="read"
      theme="light"
      allow-try="true"
      show-header="true"
      show-info="true"
      persist-auth="true">
    </rapi-doc>
  </body>
</html>
|}
;;

let redoc =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Redoc — Petstore</title>
  </head>
  <body>
    <redoc spec-url="/openapi.json"></redoc>
    <script src="https://cdn.redoc.ly/redoc/v2.5.0/bundles/redoc.standalone.js" crossorigin="anonymous"></script>
  </body>
</html>
|}
;;

let elements =
  {|<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Stoplight Elements — Petstore</title>
    <link rel="stylesheet" href="https://unpkg.com/@stoplight/elements@9.0.24/styles.min.css">
    <script src="https://unpkg.com/@stoplight/elements@9.0.24/web-components.min.js" crossorigin="anonymous"></script>
  </head>
  <body>
    <elements-api
      apiDescriptionUrl="/openapi.json"
      router="hash"
      layout="sidebar"
      tryItCredentialsPolicy="same-origin">
    </elements-api>
  </body>
</html>
|}
;;

let pages =
  [ "/docs", index
  ; "/docs/", index
  ; "/docs/swagger", swagger
  ; "/docs/scalar", scalar
  ; "/docs/rapidoc", rapidoc
  ; "/docs/redoc", redoc
  ; "/docs/elements", elements
  ]
;;
