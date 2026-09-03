# Petstore

Пример реализует полный набор путей и `operationId` официального Swagger
Petstore v3:

- `pet` — создание, полное и частичное обновление, поиск по статусу и тегам,
  получение, удаление и загрузка изображения;
- `store` — inventory, размещение, получение и удаление заказа;
- `user` — одиночное и пакетное создание, login/logout, получение, обновление
  и удаление пользователя.

Канонический контракт взят из
[OpenAPI-декларации Swagger Petstore](https://github.com/swagger-api/swagger-petstore/blob/master/src/main/resources/openapi.yaml).
Домен, сервисы и декларации маршрутов не зависят от HTTP-фреймворка.

`Pet_service`, `Order_service` и `User_service` работают только с типами из
`Domain`: они не знают о JSON, Swagger DTO и HTTP-кодах. Преобразование DTO в
доменную модель и отображение доменных ошибок в HTTP-ответы выполняются в
`Routes`. `Services` является application-scoped DI-контейнером; он и
authorization guard прикрепляются к группам через `Group.make_with_context`.
Назначение ID принадлежит сервису: отсутствующий ID генерируется, а повторный
явный ID не перезаписывает данные и отображается роутером в HTTP 409.

Официальные `findPetsByStatus` и `findPetsByTags` возвращают JSON-массивы.
Ограниченная пагинация сохранена как отдельное расширение, чтобы не менять их
wire contract:

```text
GET /pet/search?status=available&page=2&limit=20
```

`page` и `limit` необязательны и по умолчанию равны `1` и `20`; максимальный
`limit` — `100`. Ответ содержит `items` и объект `pagination` с полями `page`,
`limit`, `total` и `totalPages`. Невалидные границы возвращают стандартную
типизированную decode error с кодом 400.

Структурированные request/response body представлены JSON. XML и
`application/x-www-form-urlencoded` варианты официальной декларации намеренно
не дублируются. `uploadFile` использует настоящий
`application/octet-stream`; login возвращает JSON-строку, но демонстрационные
rate-limit response headers пока не моделируются. Поэтому пример повторяет
route surface и основные схемы, но не заявляет побайтную идентичность исходному
OpenAPI 3.0.4. Генерируемый документ остаётся OpenAPI 3.1.

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
