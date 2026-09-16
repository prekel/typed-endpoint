# История изменений

## 0.1.0 — 2026-09-16

### Добавлено

- Типизированные required/optional request и response headers с общей
  runtime/OpenAPI декларацией.
- Проверка header names и защита response values от CR/LF injection.
- Единый buffered response primitive `Backend.S.respond` с явными headers.
- Property tests для URI/query/header semantics и негейтящий router benchmark.
- `make release-check`, security policy и migration guide.
- Проверка release-архива в активном switch OCaml 5.5.1 и compile-fail
  regression tests для staged DSL и response capabilities.
- Абстрактный `Json_schema.t`, проверяемые smart constructors, типизированные
  стандартные formats и явные мосты к `ppx_deriving_jsonschema` и
  `Yojson.Safe`.
- Meta-schema regression tests для standalone-схем и полного Petstore OpenAPI.

### Изменено

- Повтор scalar query parameter теперь возвращает decode error 400 вместо
  framework-dependent выбора значения.
- Opium adapter возвращает immutable route collection, подключаемую через
  `Typed_endpoint_opium.mount`; один mount добавляет один 405/`Allow` middleware.
- Petstore login возвращает документированные `X-Rate-Limit` и
  `X-Expires-After` headers.
- Metadata, parameters, headers и contract schema больше не публикуют
  представление `Ppx_deriving_jsonschema_runtime.t`; Petstore использует общие
  `[@default]`/`[@key]` без дублирующих schema-аннотаций.
- Фиксированный response GADT заменён на масштабируемую цепочку typed cases.
  Декларации объединяются через `<|>`, handler получает status/payload-typed
  capabilities позиционно и отвечает через `respond`.
- API результата `Make` расплющен: staged DSL и `case` находятся прямо в
  `Endpoint`, а `route` и `interceptor` больше не требуют однотиповых модулей.
- HTTP method/status вынесены из `Backend.S` в общие `Method.t` и `Status.t`;
  `Status.code` централизует отображение всех именованных статусов.

### Отложено

- Разделение чистого контракта и server handler.
- Сетевой typed client.
- Streaming responses и multipart/form-data.
