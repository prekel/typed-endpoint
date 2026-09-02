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

- типы path/query/body становятся аргументами handler;
- handler может вернуть только объявленный тип ответа, а динамический status
  проверяется во время выполнения;
- JSON body ограничен по размеру (по умолчанию 1 МиБ), проверяется
  `Content-Type`, ошибки получают фиксированные статусы 400/413/415;
- именованные схемы попадают в `components/schemas`, конфликт имён отклоняется;
- `Guard` одновременно задаёт runtime-проверку и OpenAPI security requirement;
- результат OpenAPI детерминирован.

## Минимальная декларация

```ocaml
open Typed_endpoint

module Endpoint = Make (Typed_endpoint_testing)
open Endpoint
open Dsl

let route =
  make
    ~meth:B.get
    ~path:(s "health" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"Health status" ()))
  @@ fun _request () -> B.return (OK "ok")

let compiled =
  compile_exn
    [ Group.v
        ~metadata:(Operation_metadata.v ~description:"Service" ())
        [ route ]
    ]
```

`Compiled.app compiled` возвращает значение конкретного backend, а
`Compiled.openapi compiled` — тот же контракт в OpenAPI.

## Petstore

В [examples/petstore](examples/petstore/README.md) находится совместимое
подмножество Swagger Petstore v3: POST/PUT/GET/DELETE для `/pet`, поиск по
статусу, OAuth/API-key guards, DI сервиса, Swagger UI на `/docs`,
`/openapi.json` и runtime-only `/health`. Один DSL запускается через testing,
Opium, Dream и Eio.

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
```

`make check` проверяет форматирование, сборку, тесты, odoc, install targets и
сгенерированные opam-файлы. CI намеренно не добавлен.

На Ubuntu транзитивным TLS-зависимостям Opium нужен `libgmp-dev`; Dream также
может потребовать `libev-dev` и `libssl-dev`.
