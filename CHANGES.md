# История изменений

## 0.3.2 — 2026-10-16

- `Response.json` принимает необязательный `?description`: локальное описание
  имеет приоритет над description DTO, включая явно заданную пустую строку.
  `Decode_error_response.with_description` задаёт описания автоматических ошибок
  по статусу; явные ответы сохраняют приоритет. Схемы и runtime-ответы не меняются.
  Petstore публикует содержательные описания ошибок и успешного upload.
- OpenAPI использует один читаемый формат: HTTP-ответы inline, ссылки на
  именованные DTO, общие path-параметры на уровне Path Item. Автоматические
  `components.responses` и имена с хешами не создаются. Анонимные примитивы
  и коллекции остаются inline; явно заданные имена схем сохраняются.
  Пустые `parameters` и `required`, пустые operation descriptions и descriptions,
  совпадающие с summary, опускаются. Ограничения, `default`, примеры и области
  разрешения ссылок сохраняются.
- `Backend.S.respond_json` получил необязательный `?pretty:bool` с default
  `false`; собственные адаптеры должны поддержать новый аргумент. Petstore
  возвращает `/openapi.json` с отступами, обычные ответы API не меняются.
- Добавлены независимые conformance tests генерации, сериализации,
  нормализации и HTTP-контракта; Petstore проверяет покрытие всех опубликованных
  операций. `make test-js` отдельно проверяет настоящие OCaml wire fixtures,
  границы точности JS Number и lossless JSON round-trip без npm-зависимостей.
  Документирована декларативная семантика `[@jsonschema.*]`.
- Добавлены `Query.csv`, `Query.repeated`, пользовательский `Query.v` и
  `query_arg` для операторов `/!` и `/?`. Runtime и OpenAPI используют
  один способ сериализации. Scalar query-codec с array-схемой теперь
  отклоняется с `Array_query_requires_codec`.
- Petstore использует HTTP Bearer `session_auth` вместо demo OAuth.
  User service принимает `Domain.User.actor`: владелец может изменить или
  удалить свой профиль, API key и demo bearer дают административный доступ.
  Batch требует административных credentials и возвращает массив `User`.
- `UserInput` заменён на `UserCreate` и `UserUpdate`: создание требует username
  и password, полный PUT требует password и получает username из пути.
  Смена пароля и удаление атомарно отзывают все сессии пользователя через
  новый repository port `remove_by_username`.
- Исправлены CSV-декларация `tags`, строгость pagination и описание ApiResponse.

Изменения Petstore, запрет scalar array query и новое требование к реализации
`Backend.S.respond_json` несовместимы с прежним API.

## 0.3.1 — 2026-10-15

- `jsonschema.format` и поле `format` в `jsonschema.attrs` принимают
  типизированные варианты: `` `Date_time``, `` `Int32``, `` `Double`` или
  `` `Custom "my-format"``. Строковый синтаксис удалён; форматы проверяются
  по wire type, включая `option` и строковое кодирование целых.
- Удалены `ppx_schema`, `Json_schema.to_ppx` и `Json_schema.Unsafe.of_ppx`.
  Для внешних JSON-схем используйте `Json_schema.Unsafe.of_yojson`.
  В `Deriver` вместо `with_format` добавлены `with_string_format_exn`,
  `with_integer_format_exn` и `with_number_format_exn`.
- Удалены `jsonschema.compact_variants`, `polymorphic_variant_tuple` и
  строковый `jsonschema.ref`. Форма вариантов всегда соответствует Yojson;
  custom scalar предоставляет типизированную `<type>_jsonschema`.
- PPX отклоняет повторные keywords на одном узле и явные настройки
  `strict`/`additionalProperties`, противоречащие Yojson-декодеру.
  Без декодера `allow_extra_fields` теперь переопределяет `strict = true`.
- Аннотации деклараций одинаково обрабатываются в одиночных и взаимно
  рекурсивных группах, включая `format` внутри `jsonschema.attrs`.

Это несовместимые изменения публичного API. Совместимость с исходным
`ppx_deriving_jsonschema` больше не поддерживается.

## 0.3.0 — 2026-10-15

- PPX использует общие Yojson-аннотации `key`, `name`, `default` и `encoding`,
  включая префиксы `yojson.*` и `deriving.yojson.*`. Поддержаны `default`
  внутри типа поля и строковое кодирование `int64`/`nativeint`, в том числе
  в коллекциях и значениях по умолчанию.
- Удалены `jsonschema.key`, `jsonschema.name`, `jsonschema.default` и
  `jsonschema.option`. Замены: `key`, `name`, `default` и `default None`.
  Устаревшие аннотации отклоняются с подсказкой миграции. Это несовместимое
  изменение PPX API.
- При совместном выводе Yojson-декодера и схемы `additionalProperties`
  следует настройке `strict` декодера, включая его строгое значение по умолчанию.
- Релиз публикуется Git-тегом без GitHub Release. Заготовки opam используют
  исходный код из соответствующего Git-тега.

## 0.2.1 — 2026-10-13

### Добавлено

- `Request.json ~media_types` объявляет конкретные JSON media types с одним
  codec; runtime и OpenAPI используют один список.
- Petstore создаёт независимые пользовательские сессии на один час.
  Repository port и сервис остаются stateless; часы и генератор токенов
  выбираются через `Session_runtime.S` в composition root. Серверы используют
  256 бит OS entropy, тесты — детерминированные реализации.
- Добавлен `POST /user/createWithArray`; оба пакетных user endpoints возвращают
  публичные DTO без паролей.
- Добавлены регрессии HTTP-контракта, JSON Schema/PPX и Petstore sessions;
  расширены независимые wire tests и общий backend conformance suite.

### Изменено

- Маршруты завершаются только через `==>`; `handle` и `handle_with` удалены
  из публичного API. Контекст задаётся через `Group.make_with_context`,
  включая `Context.return ()` для маршрутов без зависимостей.
- `Request.json` по умолчанию принимает только `application/json`. Для vendor
  JSON требуется явный `~media_types`; wildcard и `application/+json` запрещены.
- `[@jsonschema.option]` требует общего `[@default]`, включая alias-типы,
  чтобы необязательность поля совпадала с Yojson decoder.
- Petstore login перенесён на `POST /user/login` с обязательными username и
  password в JSON body; `POST /user/logout` отзывает предъявленную сессию.
  Независимый demo bearer сохранён; для него logout возвращает 200 без отзыва.
- Входной `UserInput` отделён от публичного `User`: пароли исключены из всех
  user responses. Фиктивные `X-Rate-Limit` и `X-Expires-After` удалены из
  runtime и OpenAPI.
- `Routes.Make` принимает session repository и runtime modules; конфигурация
  загружается через `auth_from_env_exn`, отклоняющий пустой `PETSTORE_API_KEY`.
- PPX генерирует `$id` в виде URN без пути к checkout. Title Petstore согласован
  с OpenAPI 3.1; примеры приведены к текущему API.
- README описывает установку и обновление всех пакетов через GitHub pins
  на один тег, включая `v0.2.1`.

### Исправлено

- `Json_schema.nullable` сохраняет `enum`/`const`; корневой `$id` сохраняется
  при встраивании рекурсивных схем в OpenAPI.
- Типизированные маршруты отклоняют 1xx как финальный результат, тела для
  204/205/304, методы вне OpenAPI Path Item, неверные captures, пробельные и
  управляющие символы, `?`/`#` и неверные percent escapes. Статические фигурные
  скобки экранируются одинаково в OpenAPI и `Route_info`.
- Числовые параметры и headers принимают десятичный wire-формат; OCaml hex,
  underscores, hex-float, NaN и infinity отклоняются.
- Запрещены reserved request headers `Accept`/`Content-Type`/`Authorization`
  и response headers `Content-Type`/`Content-Length`/`Transfer-Encoding`/
  `Trailer`/`Connection`. Проверяются запрещённые response control characters,
  API-key header names и повторяющиеся OAuth scopes.
- OAuth authorization URLs отклоняют неверные IPv6/IPvFuture literals,
  запрещённые URI-символы, malformed percent escapes и fragments.
- Диапазоны Petstore DTO для int32/int64 учитывают фактический OCaml `int`.
  Пустой `api_key` отклоняется при аутентификации.
- Petstore Bearer parser сравнивает scheme без учёта регистра, принимает один
  или несколько SP-разделителей по RFC 6750, проверяет синтаксис токена и
  сохраняет его регистр.
- Eio разбирает router markers до однократного декодирования static segments;
  Dream сопоставляет экранированные фигурные скобки и literal percent values.
  Общий conformance suite проверяет сохранность captures без повторного decode.
- Исправлен пример `Parameter.v` в quickstart; все 35 исправленных дефектов
  отмечены в roadmap. Ядро, PPX, testing, Opium и Petstore проверены отдельно
  на OCaml 4.14.1.

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
- `make release-check` и security policy.
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
