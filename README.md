# typed-endpoint

`typed-endpoint` — типизированный DSL для HTTP API на OCaml. Одна декларация
задаёт runtime-маршрут, декодирование входных данных, допустимые ответы и
OpenAPI 3.1.

Проект разделён на независимые пакеты:

- `typed-endpoint` — framework-agnostic ядро;
- `typed-endpoint-ppx` — typed JSON Schema deriver с wire-аннотациями Yojson;
- `typed-endpoint-testing` — прямой in-memory backend для тестов без сервера;
- `typed-endpoint-opium` — интеграция с Opium 0.17.1–0.18.0;
- `typed-endpoint-dream` — интеграция с Dream 1.0.0~alpha8;
- `typed-endpoint-eio` — direct-style интеграция с cohttp-eio 6.3.

Deriver `typed-endpoint-ppx` перенесён и адаптирован на основе
[ahrefs/ppx_deriving_jsonschema](https://github.com/ahrefs/ppx_deriving_jsonschema).
Исходный copyright notice сохранён в [LICENSE](LICENSE).

## Основные гарантии

- типы path/query/header становятся аргументами handler, а body передаётся
  как типизированный `Request_body.t` и читается по требованию;
- handler получает объявленные response capabilities позиционно; каждый из них
  типизирован HTTP-статусом и payload;
- при чтении JSON body ограничен по размеру (по умолчанию 1 МиБ), проверяется
  `Content-Type`, а ошибки через `Request_body.reject` получают статусы
  400/413/415;
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
  get / "health"
  |> documented ~operation_id:"health"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Health status" ()))
  |> handle @@ fun ok () -> respond ok "ok"

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
  get
  / "pet"
  /: arg "petId" (Parameter.int64 ~description:"Pet ID" ())
  |> documented ~operation_id:"getPetById"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Pet name" ()))
  |> handle @@ fun pet_id ok () -> respond ok (Int64.to_string pet_id)
```

`/?` добавляет optional query, `/!` — required query, `header` —
required или optional typed header, `case` связывает status с codec,
`<|>` соединяет альтернативные responses, а `respond case value` формирует
типизированный ответ. `==>` завершает route для typed group. Сначала handler
получает path/query/header-параметры слева направо, затем response capabilities
в порядке `returns`, context и body. Standalone route завершается `handle`,
route со своим контекстом — `handle_with ~context`, а grouped route — `==>`.
Сырой request можно запросить
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

## Установка и первый сервер

Для Opium-приложения установите ядро и адаптер:

```sh
opam install typed-endpoint typed-endpoint-ppx typed-endpoint-opium
```

Минимальный `dune-project`:

```lisp
(lang dune 3.14)
(name hello_typed_endpoint)
```

В `dune` добавьте executable:

```lisp
(executable
 (name main)
 (libraries typed-endpoint typed-endpoint-opium))
```

`main.ml` объявляет маршрут и передаёт скомпилированные routes в существующее
Opium-приложение:

```ocaml
open! Base
open Typed_endpoint

module Endpoint = Make (Typed_endpoint_opium)

open Endpoint

let route =
  get / "health"
  |> documented ~operation_id:"health"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Health status" ()))
  |> handle @@ fun ok () -> respond ok "ok"
;;

let routes =
  compile_exn [ Group.make ~description:"Hello" [ route ] ] |> Compiled.app
;;

let () =
  Opium.App.empty
  |> Typed_endpoint_opium.mount routes
  |> Opium.App.port 8080
  |> Opium.App.run_command
;;
```

Запустите сервер и проверьте endpoint:

```sh
dune exec ./main.exe
curl -i http://127.0.0.1:8080/health
```

Ответ содержит статус `200`, `Content-Type: text/plain; charset=utf-8` и тело
`ok`.

`Response.case` статически связывает status и payload с конкретной веткой
handler. Capability другого endpoint может быть сохранена и передана в другой
handler, поэтому перед рендерингом библиотека дополнительно проверяет её
принадлежность объявленным cases и отвергает чужую capability с
`Runtime_error`.

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

Для сборки требуется Dune 3.14 или новее. Ядро, библиотека
`typed-endpoint-testing` и адаптер Opium поддерживают OCaml
4.14.1 и новее. Petstore также поддерживает OCaml 4.14.1; Dream и Eio
требуют OCaml 5.1.1 или новее.
Для полной проверки проекта локальный switch можно создать так:

```sh
make create_switch
make deps_all
make check
make release-check
make release-artifacts
make release-install-check
```

Для проверки библиотек на OCaml 4.14.1 используйте отдельный switch и
выбирайте только их цели Dune. При сборке компилятора из исходников с GCC 15
задайте C17 режим через `CC`:

```sh
CC='gcc -std=gnu17' opam switch create /tmp/typed-endpoint-ocaml-4.14.1 4.14.1
OPAMSWITCH=/tmp/typed-endpoint-ocaml-4.14.1 opam install --deps-only ./typed-endpoint.opam ./typed-endpoint-ppx.opam ./typed-endpoint-testing.opam ./typed-endpoint-opium.opam
OPAMSWITCH=/tmp/typed-endpoint-ocaml-4.14.1 opam exec -- dune build --only-packages typed-endpoint,typed-endpoint-ppx,typed-endpoint-opium,typed-endpoint-testing @install opium/test/adapter_test.exe
OPAMSWITCH=/tmp/typed-endpoint-ocaml-4.14.1 opam exec -- dune exec --only-packages typed-endpoint,typed-endpoint-ppx,typed-endpoint-opium,typed-endpoint-testing opium/test/adapter_test.exe
```

`make check` проверяет форматирование, сборку, тесты, odoc, install targets и
сгенерированные opam-файлы. CI намеренно не добавлен.

`make release-artifacts` создаёт локальный source archive, SHA-256 и заготовки
шести пакетов для opam-repository в `_release/`. `make release-install-check`
распаковывает этот archive и проверяет install targets всех пакетов, тесты,
документацию и внешние consumer-проекты в активном switch с OCaml >= 5.1.1.
Отдельный compiler при этом не устанавливается. Распакованный исходный код
остаётся в `_release/` для проверки результата.

На Ubuntu транзитивным TLS-зависимостям Opium нужен `libgmp-dev`; Dream также
может потребовать `libev-dev` и `libssl-dev`.
