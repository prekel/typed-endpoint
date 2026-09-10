# typed-endpoint

`typed-endpoint` — типизированный DSL для HTTP API на OCaml. Одна декларация
задаёт runtime-маршрут, декодирование входных данных, допустимые ответы и
OpenAPI 3.1.

Проект разделён на независимые пакеты:

- `typed-endpoint` — framework-agnostic ядро;
- `typed-endpoint-testing` — прямой in-memory backend для тестов без сервера;
- `typed-endpoint-opium` — интеграция с Opium 0.18;
- `typed-endpoint-dream` — интеграция с Dream 1.0.0~alpha8;
- `typed-endpoint-eio` — direct-style интеграция с cohttp-eio 6.3.

## Основные гарантии

- типы path/query/header/body становятся аргументами handler;
- handler может вернуть только объявленный тип ответа, а динамический status
  проверяется во время выполнения;
- JSON body ограничен по размеру (по умолчанию 1 МиБ), проверяется
  `Content-Type`, ошибки получают фиксированные статусы 400/413/415;
- именованные схемы попадают в `components/schemas`, конфликт имён отклоняется;
- компиляция отклоняет неоднозначные route-shape, повторные параметры и
  status-коды вне диапазона HTTP;
- `Guard` одновременно задаёт runtime-проверку и OpenAPI security requirement;
- route-aware interceptors получают типизированный `Route_info` с шаблоном
  пути, tags и security, но без application service locator;
- результат OpenAPI детерминирован.

## Минимальная декларация

```ocaml
open Typed_endpoint

module Endpoint = Make (Typed_endpoint_testing)
module Io = Endpoint.Io

open Io.Let_syntax
open Endpoint

let route =
  let ok = case `OK (Response.text ~description:"Health status" ()) in
  get / "health"
  |> documented ~operation_id:"health"
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun () -> respond ok "ok"

let compiled =
  compile_exn
    [ Group.make ~description:"Service" [ route ] ]
```

`Compiled.app compiled` возвращает значение конкретного backend, а
`Compiled.openapi compiled` — тот же контракт в OpenAPI. Промежуточные типы
staged DSL не позволяют добавить path segment после query, переставить request
и responses или забыть одну из стадий. Например, маршрут с path-параметром:

```ocaml
let get_pet =
  let ok = case `OK (Response.text ~description:"Pet name" ()) in
  get
  / "pet"
  /: arg "petId" (Parameter.int64 ~description:"Pet ID" ())
  |> documented ~operation_id:"getPetById"
  |> accepts Request.empty
  |> returns ok
  |> handle @@ fun pet_id () -> respond ok (Int64.to_string pet_id)
```

`/?` добавляет optional query, `/!` — required query, `header` —
required или optional typed header, `case` связывает status с codec,
`<|>` соединяет альтернативные responses, а `respond case value` формирует
типизированный ответ. `==>` завершает route для typed group. Исходные
path/query-параметры передаются handler слева направо, затем следуют context и
body. Standalone route завершается `handle`, route со своим контекстом —
`handle_with ~context`, а grouped route — `==>`. Сырой request можно запросить
явно через `Context.request`. Ошибки декодирования по умолчанию получают
безопасный JSON `{ "code": ..., "message": ... }`, который можно заменить на
уровне endpoint, группы или всей компиляции.

Если один guard/набор зависимостей используется несколькими маршрутами,
endpoint завершается `==>`, а контекст один раз прикрепляется через
`Group.make_with_context`. Его тип остаётся связан с handler каждого маршрута.

Interceptors передаются в `compile ~interceptors`. Они запускаются после
совпадения маршрута и подходят для tracing, metrics и access log по стабильному
`Route_info.path_template`. Request ID, CORS, compression и transport timeout
остаются framework middleware вокруг `Compiled.app`; авторизация и
request-scoped значения выражаются через `Guard`/`Context`.

Opium использует отдельный шаг mount: `Compiled.app` возвращает immutable
коллекцию typed routes, а `Typed_endpoint_opium.mount routes app` один раз
добавляет маршруты и общий 405/`Allow` middleware в существующее приложение.
Так старые Opium endpoint можно заменять по одному без передачи server lifecycle
библиотеке.

## Petstore

В [examples/petstore](examples/petstore/README.md) находится расширенный пример
с полным route surface Swagger Petstore v3: разделы `pet`, `store` и `user`,
бинарная загрузка изображений, отдельное пагинированное расширение,
OAuth/API-key guards, DI доменных сервисов, страница выбора Swagger UI, Scalar,
RapiDoc, Redoc и Stoplight Elements на `/docs`, `/openapi.json` и runtime-only
`/health`. Один DSL запускается через testing, Opium, Dream и Eio.

```sh
opam exec -- dune runtest examples/petstore/test
opam exec -- dune exec examples/petstore/servers/opium_server.exe
```

## Сборка

Проект использует локальный switch OCaml 5.5.0:

```sh
make create_switch
make deps_all
make check
make release-check
```

`make check` проверяет форматирование, сборку, тесты, odoc, install targets и
сгенерированные opam-файлы. CI намеренно не добавлен.

На Ubuntu транзитивным TLS-зависимостям Opium нужен `libgmp-dev`; Dream также
может потребовать `libev-dev` и `libssl-dev`.
