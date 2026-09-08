# Согласованный план развития

Этот файл фиксирует решения, принятые после сравнения `typed-endpoint` с
Servant, Tapir, Smithy4s, http4s и ZIO. Это backlog, а не описание уже
существующего публичного API.

## Реализованная основа

- Выбор database и repository adapters выполняется статически через функторы.
- Repository — stateless module; каждая операция явно получает `~conn`.
- Application service — stateless module с функциями use case. Он получает
  `~database` и определяет границу `with_connection` или `transaction`.
- Controller работает с DTO и HTTP-статусами, получает `Database.t` через
  group context и не видит `Database.connection`.
- `Order_service.place` проверяет pet и записывает order через одно и то же
  transaction-scoped соединение.
- Единственный значимый runtime-экземпляр Petstore — `Database.t`: в production
  это будет pool, в примере — copy-on-write in-memory database.

## Согласованные задачи

### Пункты 1 и 13: контракт отдельно от server logic и typed client

Нужно разделить чистое описание HTTP-контракта и его серверную реализацию:

```ocaml
let get_pet =
  Endpoint.get
    ~operation_id:"getPetById"
    ~path:(s "pet" / param "petId" Pet_id /? nil)
    ~responses:(JSON.ok Pet |+ JSON.not_found Api_response)

let get_pet_server =
  Server_endpoint.handle get_pet @@ fun pet_id database () ->
  ...
```

Один `Endpoint.t` должен интерпретироваться как OpenAPI, server route и typed
client function. Текущие curried path/query/body arguments следует сохранить:
обязательный input record и `map_input` не нужны. Record остаётся локальным
выбором приложения, когда параметров действительно много.

### Пункт 6: backend conformance suite

Нужен общий набор black-box тестов для каждого `Backend.S`: body limit,
заголовки и content type, пустой ответ, 404/405 и `Allow`, приоритет статических
маршрутов, decode errors и порядок routes. Новый backend считается готовым
только после прохождения этого suite.

### Пункт 7: типизированный `Route_info`

Runtime route должен предоставлять backend adapter или interceptor стабильные
метаданные: `operation_id`, HTTP method, route template, tags и security
requirements. Observability должна использовать template (`/pet/{petId}`), а
не raw path с высокой cardinality.

### Пункт 8: три явных уровня middleware

Нужно сохранить строгую границу:

1. framework middleware — request ID, CORS, compression, transport timeout;
2. route-aware interceptor — tracing, metrics и логирование с `Route_info`;
3. `Context`/`Guard` — типизированные request-scoped значения и авторизация.

Interceptor не должен превращаться в service locator или получать доступ к
произвольным application dependencies.

### Пункт 9: request-scoped значения и `Principal.t`

Следует расширить существующие `Dependency`/`Guard`, а не создавать отдельный
аналог http4s `ContextMiddleware`. Успешный guard должен возвращать
типизированный `Principal.t`; вместе с ним через applicative context можно
передавать request ID, trace context и другие дешёвые request-scoped значения.
Petstore должен показать этот подход на защищённой группе.

### Пункт 14: независимые wire contract tests

Нужны тесты сырого HTTP boundary и fake transport, которые не используют один
и тот же codec для подготовки запроса и проверки ответа. Они должны ловить
совместимые на уровне OCaml типов, но неправильные JSON field names, status,
headers и content types.

## Не планируется сейчас

- Обязательный endpoint-specific response ADT вместо текущей типизированной
  цепочки responses.
- Аналог Servant `NamedRoutes`: controller modules уже дают осмысленную
  группировку без record boilerplate.
- Runtime service locator, type-map, `Layer` или `Resource` в HTTP-ядре.
- Обязательная упаковка curried handler arguments в input record.
- Универсальный `hoist` эффектов; вернуться к нему стоит только после появления
  второго практического интерпретатора одной application algebra.
