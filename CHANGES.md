# История изменений

## 0.2.0 — 2026-10-02

### Добавлено

- Типизированный `Request_body.t` для отложенного, ограниченного и повторно
  используемого чтения JSON, text и binary в handler; `Request_body.reject`
  сохраняет настройку decode-error response.
- Отдельный `typed-endpoint-ppx`: перенос и адаптация
  [`ahrefs/ppx_deriving_jsonschema`](https://github.com/ahrefs/ppx_deriving_jsonschema)
  для typed JSON Schema DTO с поддержкой OCaml 4.14.1 и общих wire-аннотаций
  `ppx_deriving_yojson`.
- Поддержаны JSON Schema `title` и `description`, в том числе через
  `[@jsonschema.attrs { title = ...; description = ... }]`.
- PPX теперь собирает `Json_schema.t` через типизированные конструкторы; он не
  генерирует дерево Yojson и не импортирует его через `Unsafe.of_yojson`.
- Добавлены регрессии для required-семантики option alias и `$defs` из
  рекурсивной схемы другого модуля.
- `Json_schema.t` параметризован типом DTO; схемы из нетронутого
  `ppx_deriving_jsonschema` импортируются через `Json_schema.Unsafe.of_ppx`.
- Схемы записей допускают дополнительные поля по умолчанию; атрибут
  `[@@jsonschema.disallow_extra_fields]` включает строгую проверку.
- Удалён `~variant_as_string`, который терял payload вариантов; для вариантов
  без payload используется `[@@jsonschema.compact_variants]`.

### Изменено

- Handler для `Request.json`, `Request.text` и `Request.binary` теперь
  получает `Request_body.t`. Вызовите `Request_body.read` и обработайте
  `Result`; `Request_body.reject` сохраняет настроенный ответ для ошибок
  декодирования. Чтение и проверка `Content-Type` выполняются по требованию.
- Petstore и Opium adapter работают на OCaml 4.14.1; Dream и Eio по-прежнему
  требуют OCaml 5.1.1 или новее.

## 0.1.1 — 2026-09-24

- Минимальная версия OCaml снижена до 5.1.1 для всех пакетов; Eio adapter
  использует Eio >= 1.2 при сохранении cohttp-eio 6.3.0.

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
