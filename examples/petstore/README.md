# Petstore

## Структура

```text
domain/          доменная модель и её инварианты
application/     repository ports, сервисы и типизированный контейнер
infrastructure/  in-memory реализации портов и development composition root
http/            DTO, guards, контроллеры и сборка маршрутов
servers/         entrypoint для Opium, Dream и Eio
test/            тесты сервисов и HTTP-контракта без запуска сервера
```

Поддиректории входят в одну Dune-библиотеку через
`include_subdirs unqualified`. Поэтому слои видны в файловой структуре, но
существующий OCaml API сохраняется: например, `Petstore_app.Domain` и
`Petstore_app.Routes` не получают дополнительного уровня вложенности.

Пример реализует полный набор путей и `operationId` официального Swagger
Petstore v3:

- `pet` — создание, полное и частичное обновление, поиск по статусу и тегам,
  получение, удаление и загрузка изображения;
- `store` — inventory, размещение, получение и удаление заказа;
- `user` — одиночное и пакетное создание, login/logout, получение, обновление
  и удаление пользователя.

Канонический контракт взят из
[OpenAPI-декларации Swagger Petstore](https://github.com/swagger-api/swagger-petstore/blob/master/src/main/resources/openapi.yaml).
Домен и сервисы не зависят от HTTP-фреймворка. HTTP-часть разделена на
`Pet_controller`, `Store_controller` и `User_controller`; `Routes` только
собирает их группы и служебные endpoints.

## DI и слои приложения

Зависимости задаются явно в два этапа:

1. `Pet_repository.S`, `Order_repository.S` и `User_repository.S` являются
   портами хранения с абстрактным эффектом `'a io`;
2. функторы `*_service.Make` получают реализации портов. `Order_service.Make`
   дополнительно получает `Pet_service.S`, поэтому правило «заказываемый pet
   существует» видно в графе зависимостей и проверяется вне HTTP;
3. контроллеры получают значения готовых сервисов через `create`;
4. `Routes.Make_with_services` принимает модули сервисов, а `Services.v` — их
   application-scoped экземпляры.

`Memory_services.Make` — development composition root с изолированными
in-memory репозиториями. `Routes.Make` использует его по умолчанию, поэтому
entrypoint сервера остаётся коротким:

```ocaml
module App = Petstore_app.Routes.Make (Typed_endpoint_opium)

let services = App.Services.create ()
let compiled = App.compile ~auth:(Petstore_app.Routes.auth_from_env ()) services
```

В production composition root вместо `Pet_repository_memory.Make` можно
подставить модуль с тем же `Pet_repository.S`, где `type 'a io = 'a Lwt.t`, а
внутри использовать пул соединений PGOCaml. После этого собираются
`Pet_service.Make (Io) (Pg_pet_repository)` и остальные сервисы, а в
`Routes.Make_with_services` передаются получившиеся модули. Ни домен, ни DTO,
ни контроллеры при этом не меняются.

`Pet_service`, `Order_service` и `User_service` работают только с типами из
`Domain`: они не знают о JSON, Swagger DTO и HTTP-кодах. Преобразование DTO и
выбор статуса выполняют контроллеры. Ошибки инфраструктуры отображаются в
объявленный HTTP 503 с очищенным сообщением. Контроллер вместе с guard
прикрепляется к группе через `Group.make_with_context`, поэтому runtime DI и
OpenAPI security используют одну декларацию.

Назначение ID принадлежит репозиторию: отсутствующий ID генерируется, а
повторный явный ID не перезаписывает данные и отображается контроллером в HTTP
409.

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
`PETSTORE_API_KEY`. Исходный OpenAPI доступен по `/openapi.json`, health check —
по `/health`.

На `/docs` находится страница выбора пяти OpenAPI renderer:

- `/docs/swagger` — Swagger UI 5.32.14;
- `/docs/scalar` — Scalar 1.67.0;
- `/docs/rapidoc` — RapiDoc 9.3.8;
- `/docs/redoc` — Redoc 2.5.0;
- `/docs/elements` — Stoplight Elements 9.0.24.

Все они читают один сгенерированный `/openapi.json` и загружают закреплённые
версии assets с CDN. Эти служебные маршруты намеренно не входят в контракт
OpenAPI. Для полностью автономного развёртывания assets следует раздавать
локально.
