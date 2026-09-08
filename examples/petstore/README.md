# Petstore

## Структура

```text
domain/          доменная модель и её инварианты
application/     repository ports и сервисы
infrastructure/  in-memory реализации портов
http/            DTO, guards, контроллеры и сборка маршрутов
servers/         composition root и entrypoint для Opium, Dream и Eio
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

Зависимости задаются явно на двух разных уровнях:

1. `Pet_repository.S`, `Order_repository.S` и `User_repository.S` являются
   stateless-портами хранения с абстрактными эффектом `'a io` и типом
   `connection`; каждая операция явно принимает `~conn`;
2. `Database.S` абстрагирует долгоживущий pool/state, выдачу соединения и
   транзакции;
3. функторы `*_service.Make` получают database и реализации портов.
   `Order_service.Make` получает pet и order repositories, поэтому правило
   «заказываемый pet существует» видно в графе зависимостей, проверяется вне
   HTTP и выполняется в одной транзакции с записью заказа;
4. функторы контроллеров получают stateless-модули готовых сервисов;
5. `Routes.Make` связывает весь статический граф database/repository → service →
   controller и проверяет, что каждый узел использует эффект выбранного
   backend;
6. серверный composition root создаёт единственный application runtime resource
   `Database.t` и передаёт его в `App.compile` именованным аргументом.

Например, in-memory composition root Opium выглядит так:

```ocaml
module Backend = Typed_endpoint_opium
module Database = Petstore_app.Database_memory.Make (Backend.Io)

module App =
  Petstore_app.Routes.Make
    (Backend)
    (Database)
    (Database.Pet_repository)
    (Database.Order_repository)
    (Database.User_repository)

let compiled =
  App.compile
    ~auth:(Petstore_app.Routes.auth_from_env ())
    ~database:(Database.create ())
```

В production composition root вместо `Database_memory.Make` можно подставить
Caqti-адаптер. В нём `Database.t` представляет pool, а
`Database.connection` — scoped connection Caqti. Три repository adapters не
хранят pool: они реализуют запросы с явным `~conn`. Пул приобретается и
освобождается в executable, а его значение передаётся в `App.compile`.
Сервисы и контроллеры при этом остаются stateless и автоматически строятся
внутри статически выбранного графа; ни домен, ни DTO не меняются.

Здесь нет runtime service locator: по типу или имени ничего не ищется, а
реализацию нельзя случайно подменить внутри запроса. Runtime-значение всё же
остаётся: состояние in-memory database или production pool существует только
во время работы процесса.

`Pet_service`, `Order_service` и `User_service` работают только с типами из
`Domain`: они не знают о JSON, Swagger DTO и HTTP-кодах. Преобразование DTO и
выбор статуса выполняют контроллеры. Ошибки инфраструктуры отображаются в
объявленный HTTP 503 с очищенным сообщением. Контроллер вместе с guard
прикрепляется к группе через `Group.make_with_context`: `Context` доставляет
уже собранную dependency в handler на уровне запроса, но не выбирает и не
создаёт application services. OpenAPI security и runtime guard используют одну
декларацию. В context передаётся `Database.t`, но никогда не scoped
`Database.connection`: границу транзакции определяет application service.

Обоснование этой границы и сравнение с Servant, Tapir, Smithy4s, http4s и ZIO
собраны в [заметке о типизированных FP-фреймворках](../../doc/typed-fp-framework-lessons.md).

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

## Access log

Все три server entrypoint пишут access log в `stderr`: ровно один компактный
JSON-объект на строку. Плоский формат содержит `timestamp`, `level`, `event`,
`request_id`, `method`, `path`, `status` и `duration_ms`. Успешный ответ
возвращает тот же идентификатор в `X-Request-Id`.

```json
{"timestamp":"2026-09-08T12:00:00.123Z","level":"info","event":"http_request","request_id":"gateway-42","method":"GET","path":"/pet/42","status":200,"duration_ms":12.5}
```

Входящий `X-Request-Id` сохраняется, если содержит от 1 до 128 латинских букв,
цифр, `.`, `_` или `-`; иначе сервер генерирует новый. Это позволяет связать
событие приложения с reverse proxy или API gateway без доверия к произвольным
значениям заголовка.

В целях безопасности access log намеренно не содержит query string, request
body, response body и `Authorization`. Необработанное исключение записывается
как событие с `level: "error"` и полем `error`, после чего передаётся
фреймворку; поэтому
поток логов должен быть доступен только доверенной инфраструктуре. Duration
измеряет выполнение middleware и handler до подготовки ответа, а не передачу
байтов клиенту.

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
