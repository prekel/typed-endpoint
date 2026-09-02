# Petstore

Пример реализует pet-часть Swagger Petstore v3: добавление, обновление,
поиск по статусу, получение и удаление питомца. Доменный сервис и декларации
маршрутов не зависят от HTTP-фреймворка.

Пути, `operationId` и JSON-поля сверены с официальной
[OpenAPI-декларацией Swagger Petstore](https://github.com/swagger-api/swagger-petstore/blob/master/src/main/resources/openapi.yaml).
Документ проекта остаётся OpenAPI 3.1 и не пытается побайтно повторить исходный
YAML 3.0.4.

Проверка без сервера и сокетов:

```sh
opam exec -- dune runtest examples/petstore/test
```

Запуск адаптеров:

```sh
opam exec -- dune exec examples/petstore/servers/opium_server.exe
opam exec -- dune exec examples/petstore/servers/dream_server.exe
opam exec -- dune exec examples/petstore/servers/eio_server.exe
```

По умолчанию принимаются `Authorization: Bearer demo-token` и
`api_key: demo-key`. Значения можно заменить через `PETSTORE_BEARER_TOKEN` и
`PETSTORE_API_KEY`. Swagger UI доступен по `/docs`, исходный OpenAPI — по
`/openapi.json`, health check — по `/health`. Эти служебные маршруты намеренно
не входят в контракт OpenAPI. UI загружает закреплённую версию
`swagger-ui-dist` 5.32.14 с CDN; для полностью автономного развёртывания assets
следует раздавать локально.
