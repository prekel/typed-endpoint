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

### Пункты 1 и 13: контракт и сетевой typed client — отложено

Направление не входит в ближайший release. Публичная запись маршрута остаётся
единой: после `returns` сразу идут `==>` и серверный handler. Пользователь не
должен выносить каждую декларацию в отдельный `Contract.Staged` и затем
привязывать handler вторым объявлением. Сохраняются curried аргументы path,
query и body; обязательный input record и `map_input` не нужны.

Для клиента на OCaml, включая браузерную сборку через `js_of_ocaml`, нужны
следующие возможности:

1. Внутри библиотеки отделить типизированное описание HTTP-контракта от
   серверного handler и `Make (Backend)`. Итоговый серверный endpoint содержит
   оба, но клиентский артефакт должен собираться без handler, Opium, Dream,
   Eio и серверных application-зависимостей. Спроектировать генерацию этого
   артефакта из того же исходного объявления на этапе сборки; способ извлечения
   из DSL определить на прототипе, не вводя вторую публичную декларацию.
2. Добавить необходимые обратные направления кодеков: `Parameter.S` сейчас
   только разбирает path/query, `Request_payload.S` только декодирует body, а
   `Response_payload.S` только кодирует ответ. Клиент должен кодировать
   path/query/headers и request body, затем декодировать статус, headers и
   response body. Серверные endpoint без клиентских кодеков должны оставаться
   пригодными для сервера и OpenAPI; получение клиента для них должно давать
   понятную ошибку сборки.
3. Сделать ядро сетевого клиента независимым от транспорта и отдельный адаптер
   для браузера на `js_of_ocaml`/Fetch. Клиент принимает base URL и данные
   авторизации явно, сохраняет правила percent-encoding и query-параметров
   сервера. Объявленные HTTP-ответы возвращаются с типами их payload; ошибка
   сети, неожиданный статус и невалидный body различаются отдельно.
4. Позволить клиенту и серверу компилировать одни и те же чистые доменные
   модули и DTO/кодеки. Клиентский артефакт ссылается на эти OCaml-типы, а не
   восстанавливает их из OpenAPI как новые record-типы. Если wire shape не
   совпадает с доменной сущностью, используется отдельная общая read model:
   например, элемент списка статей может не содержать `body` и внутренний ID.
5. Добавить небольшой пример `js_of_ocaml`: серверный маршрут остаётся с
   inline handler, браузерный клиент вызывает тот же endpoint через Fetch,
   использует общий доменный тип параметра и разбирает несколько объявленных
   статусов. Проверить соответствие клиентского запроса и ответа серверному
   runtime и сгенерированному OpenAPI.

OpenAPI остаётся внешним описанием и основой для SDK на других языках. Для
собственного OCaml-клиента он не должен быть единственным источником типов:
схема JSON не хранит идентичность доменных OCaml-модулей.

### Этап 3: production HTTP semantics и адаптеры — реализовано

- Добавлены типизированные required/optional request и response headers с общей
  runtime/OpenAPI декларацией, проверкой имён и защитой от CR/LF injection.
- Scalar query больше не зависит от first/last policy framework: повтор имени
  получает предсказуемую decode error 400, а запятая внутри одного value
  сохраняется.
- `Backend.S.respond` принимает готовые headers/body; convenience responders
  сохраняют канонические content types и поведение body-less ответа.
- Opium `app_builder` стал immutable route collection. `mount` регистрирует один
  общий 405/`Allow` middleware и позволяет заменять старые Opium routes по одному.
- Exception boundary, cancellation, timeout, CORS и compression остаются
  ответственностью framework middleware; typed-endpoint не владеет lifecycle.

### Этап 4: проверки и release hardening — реализовано

- Backend conformance расширен typed headers и duplicate scalar query.
- Добавлены QCheck properties для percent-decoding, регистра headers, повторных
  query values и приоритета static route, а также отдельный негейтящий router
  benchmark.
- Petstore login публикует и возвращает `X-Rate-Limit` и `X-Expires-After`; wire
  tests проверяют значения без повторного использования application codecs.
- Добавлены changelog, security policy, migration guide и `make release-check`.
- Матрица поддерживаемых adapter versions и эксплуатационные границы подробно
  описаны в `doc/production.mld`.

### Пункт 6: backend conformance suite — реализовано

`Typed_endpoint_testing.Backend_conformance` содержит общий black-box suite для
`Backend.S`: ограничение body, регистронезависимые заголовки, content type,
пустой ответ, 404/405 и `Allow`, приоритет статического маршрута, path capture,
decode errors и порядок `Backend.combine`. Suite подключён к testing, Opium,
Dream и Eio adapter tests. Новый backend должен предоставить небольшой harness
преобразования request/response и запустить тот же suite.

### Пункт 7: типизированный `Route_info` — реализовано

После совпадения маршрута interceptor получает `Route_info.t` с
`operation_id`, HTTP method, OpenAPI-style route template, итоговыми tags и
security requirements. Метаданные строятся из той же декларации, что runtime и
OpenAPI. Petstore access log использует `/pet/{petId}`, а не raw path с высокой
cardinality.

### Пункт 8: три явных уровня middleware — реализовано

Сохранена строгая граница:

1. framework middleware — request ID, CORS, compression, transport timeout;
2. route-aware interceptor — tracing, metrics и логирование с `Route_info`;
3. `Context`/`Guard` — типизированные request-scoped значения и авторизация.

Framework middleware остаётся API конкретного адаптера. `interceptor`
подключается через `compile ~interceptors`, выполняется только для совпавшего
typed route и получает лишь `Route_info`, raw request и `next`. Поэтому он не
может превратиться в service locator или получить произвольные application
dependencies. В Petstore request-ID middleware работает до router, access-log
interceptor — после совпадения route, а guard/context остаются частью typed
endpoint.

### Пункт 9: request-scoped значения и `Principal.t` — реализовано

`Principal.t` хранит application-defined identity и детерминированный набор
scopes. `Guard.authenticate` возвращает его как обычный typed context, поэтому
principal компонуется с `Dependency.of_request` и application dependency через
`Context.Let_syntax`. Защищённые группы Petstore передают handler значение
`Controller_context.Secured.t` с principal, request ID и статически выбранной
dependency; connection и runtime service locator туда не попадают.

### Пункт 14: независимые wire contract tests — реализовано

`examples/petstore/test/wire_contract_test.ml` отправляет literal HTTP body
через in-memory transport и независимо разбирает сырой ответ. Тесты не
используют application codecs для подготовки ожидаемых данных и проверяют JSON
field names, status, headers, content types, decode-error shape, пустые ответы
и router 404.

## Не планируется сейчас

- Обязательный endpoint-specific response ADT вместо текущей типизированной
  цепочки responses.
- Аналог Servant `NamedRoutes`: controller modules уже дают осмысленную
  группировку без record boilerplate.
- Runtime service locator, type-map, `Layer` или `Resource` в HTTP-ядре.
- Обязательная упаковка curried handler arguments в input record.
- Универсальный `hoist` эффектов; вернуться к нему стоит только после появления
  второго практического интерпретатора одной application algebra.
