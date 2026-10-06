# typed-endpoint

`typed-endpoint` — типизированный DSL для HTTP API на OCaml. Одна декларация
задаёт runtime-маршрут, декодирование входных данных, допустимые ответы и
OpenAPI 3.1.

Проект разделён на независимые пакеты:

- `typed-endpoint` — framework-agnostic ядро;
- `typed-endpoint-ppx` — typed JSON Schema deriver с wire-аннотациями Yojson;
- `typed-endpoint-testing` — прямой in-memory backend для тестов без сервера;
- `typed-endpoint-opium` — интеграция с Opium >= 0.17.1 и < 0.19.0;
- `typed-endpoint-dream` — интеграция с Dream 1.0.0~alpha8;
- `typed-endpoint-eio` — direct-style интеграция с cohttp-eio 6.3.

Deriver `typed-endpoint-ppx` перенесён и адаптирован на основе
[ahrefs/ppx_deriving_jsonschema](https://github.com/ahrefs/ppx_deriving_jsonschema).

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
open! Base
open Typed_endpoint

module Endpoint = Make (Typed_endpoint_testing)

open Endpoint

let route =
  get / "health"
  |> documented ~operation_id:"health"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Health status" ()))
  ==> fun ok () () -> respond ok "ok"

let compiled =
  compile_exn
    [ Group.make_with_context
        ~description:"Service"
        ~context:(Context.return ())
        [ route ]
    ]
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
  |> returns (case `OK (Response.text ~description:"Pet ID" ()))
  ==> fun pet_id ok () () -> respond ok (Int64.to_string pet_id)
```

`/?` добавляет optional query, `/!` — required query, `header` —
required или optional typed header, функция `case` связывает status с codec,
`<|>` соединяет альтернативные responses, а `respond case value` формирует
типизированный ответ. `==>` завершает маршрут для `Group.make_with_context`.
Handler получает path/query/header-параметры слева направо, затем response
capabilities в порядке `returns`, значение контекста группы и request body.
Если зависимости не нужны, передайте `Context.return ()`. Сырой request можно
получить через `Context.request`. Ошибки декодирования по умолчанию получают
безопасный JSON `{ "code": ..., "message": ... }`, который можно заменить на
уровне endpoint, группы или всей компиляции.

Для `Request.json`, `Request.text` и `Request.binary` последний аргумент
handler — `Request_body.t`. Вызов `Request_body.read` возвращает `Result` в
эффекте backend; `Request_body.reject` применяет настроенный ответ при ошибке.
Тело и `Content-Type` проверяются только при первом чтении.

Если один guard или набор зависимостей используется несколькими маршрутами,
контекст один раз прикрепляется через `Group.make_with_context`. Его тип
остаётся связан с handler каждого маршрута.

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

Чтобы установить версию `v0.2.0` из исходников, получите тег и установите
нужные для примера пакеты:

```sh
git clone --branch v0.2.0 --depth 1 https://github.com/prekel/typed-endpoint.git
cd typed-endpoint
opam install ./typed-endpoint.opam ./typed-endpoint-ppx.opam ./typed-endpoint-opium.opam
```

Создайте каталог приложения:

```sh
mkdir ../hello_typed_endpoint
cd ../hello_typed_endpoint
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
 (libraries base yojson typed-endpoint typed-endpoint-opium)
 (preprocess
  (pps ppx_let ppx_deriving_yojson typed-endpoint-ppx)))
```

`main.ml` объявляет маршрут и подключает скомпилированные routes к
Opium-приложению:

```ocaml
open! Base
open Typed_endpoint

module Endpoint = Make (Typed_endpoint_opium)
module Io = Endpoint.Io

open Io.Let_syntax
open Endpoint

module Greeting = struct
  type t = { name : string } [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Name to greet" ()
  ;;
end

let route =
  post / "hello"
  |> documented ~operation_id:"sayHello"
  |> accepts (Request.json (module Greeting))
  |> returns
       (case `OK (Response.text ~description:"Greeting" ())
        <|> case `Unprocessable_entity (Response.text ~description:"Empty name" ()))
  ==> fun ok invalid () body ->
      let%bind result = Request_body.read body in
      match result with
      | Error error -> Request_body.reject error
      | Ok greeting when String.is_empty greeting.name ->
        respond invalid "name is required"
      | Ok greeting -> respond ok ("Hello, " ^ greeting.name)
;;

let routes =
  compile_exn
    [ Group.make_with_context
        ~description:"Hello"
        ~context:(Context.return ())
        [ route ]
    ]
  |> Compiled.app
;;

let () =
  Opium.App.empty
  |> Typed_endpoint_opium.mount routes
  |> Opium.App.port 8080
  |> Opium.App.run_command
;;
```

Запустите сервер:

```sh
dune exec ./main.exe
```

В другом терминале проверьте три варианта ответа:

```sh
curl -i -X POST http://127.0.0.1:8080/hello -H 'Content-Type: application/json' --data '{"name":"Ada"}'
curl -i -X POST http://127.0.0.1:8080/hello -H 'Content-Type: application/json' --data '{"name":""}'
curl -i -X POST http://127.0.0.1:8080/hello -H 'Content-Type: application/json' --data '{'
```

Первый запрос возвращает `200` и `Hello, Ada`, второй — объявленный `422`,
третий — автоматический JSON-ответ `400` для невалидного тела. Текстовые ответы
имеют `Content-Type: text/plain; charset=utf-8`.

Функция `case` статически связывает status и payload с конкретной веткой
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

## Совместимость и ограничения

Требуется Dune 3.14 или новее.

| Пакеты | Минимальный OCaml | Версии HTTP-библиотек |
| --- | --- | --- |
| `typed-endpoint`, `typed-endpoint-ppx`, `typed-endpoint-testing` | 4.14.1 | — |
| `typed-endpoint-opium` | 4.14.1 | Opium >= 0.17.1 и < 0.19.0 |
| `typed-endpoint-dream` | 5.1.1 | Dream 1.0.0~alpha8 |
| `typed-endpoint-eio` | 5.1.1 | cohttp-eio 6.3.0, Eio >= 1.2 |

Petstore с Opium также работает на OCaml 4.14.1. Сейчас один endpoint объявляет
один формат request body; multipart/form-data и streaming responses не входят
в API. Подробности — в [руководстве по эксплуатации](doc/production.mld).

## Разработка

Для полной локальной проверки в switch OCaml 5.1.1 или новее:

```sh
make deps_all
make check
```

`make check` включает форматирование, сборку, тесты, odoc, install targets и
проверку пакетов. Подготовка релиза и проверка OCaml 4.14.1 описаны в
[руководстве по эксплуатации](doc/production.mld).

## Документация

- [Быстрый старт и DTO](doc/quickstart.mld)
- [Эксплуатация и ограничения](doc/production.mld)
- [История изменений](CHANGES.md)
- [План развития](doc/roadmap.md)
- [Сообщение об уязвимости](SECURITY.md)
