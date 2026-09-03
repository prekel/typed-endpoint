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
module Io = Endpoint.Io

open Io.Let_syntax
open Endpoint
open Dsl

let route =
  make
    ~meth:B.get
    ~path:(s "health" /? nil)
    ~request:Request.empty
    ~responses:(ok (Response.text ~description:"Health status" ()))
  @@ fun () -> return (OK "ok")

let compiled =
  compile_exn
    [ Group.make ~description:"Service" [ route ] ]
```

`Compiled.app compiled` возвращает значение конкретного backend, а
`Compiled.openapi compiled` — тот же контракт в OpenAPI.

Обычный `make` передаёт handler только path/query-параметры и body. Для
типизированных зависимостей и авторизации служит `make_with ~context`; сырой
request доступен явно через `Context.request`. Ошибки декодирования по умолчанию
получают безопасный JSON `{ "code": ..., "message": ... }`, который можно
заменить на уровне endpoint, группы или всей компиляции.

Если один guard/набор зависимостей используется несколькими маршрутами,
endpoint объявляется через `make_in_group`, а контекст один раз прикрепляется
через `Group.make_with_context`. Его тип остаётся связан с handler каждого
маршрута.

## Petstore

В [examples/petstore](examples/petstore/README.md) находится расширенный пример
с полным route surface Swagger Petstore v3: разделы `pet`, `store` и `user`,
бинарная загрузка изображений, отдельное пагинированное расширение,
OAuth/API-key guards, DI доменных сервисов, Swagger UI на `/docs`,
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
