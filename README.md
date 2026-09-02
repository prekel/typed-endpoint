# typed-endpoint

`typed-endpoint` — экспериментальный типизированный DSL для описания
HTTP API. Одни и те же декларации используются для сборки runtime-маршрутов и
генерации OpenAPI 3.1.0.

Репозиторий содержит два production-пакета:

- `typed-endpoint` — framework-agnostic ядро с описанием путей, запросов,
  ответов и OpenAPI;
- `typed-endpoint-opium` — адаптер для Opium.

## Структура

```text
lib/     ядро и публичный модуль Typed_endpoint
opium/   адаптер Typed_endpoint_opium
  test/    демонстрационные маршруты, OpenAPI snapshot и тестовый сервер
  doc/     проектные решения и примеры для DI и Guard
```

Ядро зависит от `Base`, `Lwt` и `Yojson`, но не зависит от Opium. Интеграция с
web-framework реализуется через `Typed_endpoint.Backend.S`.

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

В Ubuntu для транзитивных TLS-зависимостей Opium нужен системный пакет
`libgmp-dev`.

`make fmt` только проверяет форматирование и не изменяет исходники.
