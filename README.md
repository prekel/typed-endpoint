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
```

Ядро зависит от `Base`, `Lwt` и `Yojson`, но не зависит от Opium. Интеграция с
web-framework реализуется через `Typed_endpoint.Backend.S`.

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
