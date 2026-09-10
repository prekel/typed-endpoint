# История изменений

## Не выпущено

### Добавлено

- Типизированные required/optional request и response headers с общей
  runtime/OpenAPI декларацией.
- Проверка header names и защита response values от CR/LF injection.
- Единый buffered response primitive `Backend.S.respond` с явными headers.
- Property tests для URI/query/header semantics и негейтящий router benchmark.
- `make release-check`, security policy и migration guide.
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
- Фиксированный response GADT заменён на масштабируемые typed
  `Response.case` tokens. Каждый status получает собственный payload type,
  декларации объединяются через `<|>`, а handlers отвечают через `respond`.

### Отложено

- Разделение чистого контракта и server handler.
- Сетевой typed client.
- Streaming responses и multipart/form-data.
