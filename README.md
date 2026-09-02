# typed-endpoint

`typed-endpoint` — экспериментальный типизированный DSL для описания
HTTP API. Одни и те же декларации используются для сборки runtime-маршрутов и
генерации OpenAPI 3.1.0.

Репозиторий содержит четыре production-пакета:

- `typed-endpoint` — framework-agnostic ядро с описанием путей, запросов,
  ответов и OpenAPI;
- `typed-endpoint-opium` — адаптер для Opium;
- `typed-endpoint-dream` — адаптер для Dream;
- `typed-endpoint-eio` — нативный Eio-адаптер на `cohttp-eio` со встроенным
  минимальным router.

## Структура

```text
lib/     ядро и публичный модуль Typed_endpoint
opium/   адаптер Typed_endpoint_opium
dream/   адаптер Typed_endpoint_dream
eio/     адаптер Typed_endpoint_eio
test/    демонстрационные маршруты, OpenAPI snapshot и тестовый сервер
example/ backend-independent пример приложения и точки запуска серверов
doc/     проектные решения и примеры для DI и Guard
```

Ядро зависит от `Base` и `Yojson`, но не зависит от HTTP server или async
runtime. Интеграция реализуется через `Typed_endpoint.Backend.S`: Lwt-backends
используют `type 'a io = 'a Lwt.t`, а Eio — direct style `type 'a io = 'a`.

## HTTP backends

Для Opium и Dream `Compiled.app` преобразуется в framework application:

```ocaml
let opium_app = Opium.App.empty |> Compiled.app compiled
let dream_handler = Compiled.app compiled |> Typed_endpoint_dream.router
```

Eio-адаптер возвращает `Cohttp_eio.Server.t`:

```ocaml
let server = Compiled.app compiled |> Typed_endpoint_eio.server

Eio_main.run @@ fun env ->
Eio.Switch.run @@ fun sw ->
let socket =
  Eio.Net.listen
    ~sw
    ~backlog:128
    (Eio.Stdenv.net env)
    (`Tcp (Eio.Net.Ipaddr.V4.any, 8080))
in
Cohttp_eio.Server.run ~on_error:Stdlib.raise socket server
```

В Eio handler возвращает typed response напрямую; `Lwt.return` не требуется.
Через `Typed_endpoint_eio.Request.http/header` доступны исходный request и
заголовки.

## Real-world пример

В [`example/realworld`](example/realworld/README.md) находится небольшой API
статей. Домен, сервис, DTO и декларации маршрутов не зависят от HTTP-фреймворка.
Один и тот же функтор маршрутов компилируется для локального memory backend,
Opium, Dream и Eio.

Тест не поднимает сокет и не использует web framework:

```sh
opam exec -- dune runtest --root . example/realworld/test
```

Сервер можно запустить на любом из поддерживаемых backend:

```sh
opam exec -- dune exec --root . example/realworld/servers/opium_server.exe
opam exec -- dune exec --root . example/realworld/servers/dream_server.exe
opam exec -- dune exec --root . example/realworld/servers/eio_server.exe
```

## Компиляция деклараций

Маршруты сначала собираются в единый проверенный контракт, а затем из него
получается OpenAPI и runtime-приложение:

```ocaml
open Typed_endpoint.Make (Typed_endpoint_opium)

let parse_errors =
  D.Parse_error_response.json
    ~status:`Bad_request
    ~payload:(module Error_response)
    ~map:Error_response.of_parse_error

let compiled = D.compile_exn ~parse_error:parse_errors groups
let app = D.Compiled.app compiled
let openapi = D.Compiled.openapi compiled
```

`D.compile` возвращает список ошибок, если повторяется метод и путь,
`operationId` или HTTP-статус, если status-family пуста, либо если маршрут с
декодированием параметров/body не получил parse-error policy. Политика может
быть задана на endpoint, группе или при `compile`; применяется первый вариант
в этом порядке.

JSON-форма ответа всегда задаётся явно через `D.Response.json`. Пагинация и
envelope являются обычными response DTO конкретного endpoint, а не скрытой
глобальной настройкой.

`D.no_content` задаёт именно `204` и допускает только `No_content` в
handler; декларации `204` с text/JSON payload отклоняются при компиляции.
Для маршрута, который намеренно не входит в OpenAPI, используйте
`D.Unsafe.route`; это явное исключение из общей декларации.

Типизированные DI и Guard описаны в
[doc/di.md](doc/di.md) и [doc/guard.md](doc/guard.md).

## Сборка

Проект рассчитан на локальный opam switch с OCaml 5.5.0:

```sh
make create_switch
make deps_all
make build
make test
make fmt
```

В Ubuntu нужны системные пакеты `libgmp-dev` для транзитивных TLS-зависимостей
Opium, а для Dream — `libev-dev` и `libssl-dev`.

`make fmt` только проверяет форматирование и не изменяет исходники.
