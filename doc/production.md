# Эксплуатация

## Ограничения body

JSON по умолчанию принимается для `application/json`; конкретные vendor types
задаются через `Request.json ~media_types`. Content-Type допускает параметры.
Runtime и OpenAPI используют один список типов с одним codec и схемой;
суффиксный wildcard `application/*+json` и `application/+json` запрещены.
Текст принимается как `text/plain`. Backend обязан остановить буферизацию после
`max_body_bytes`; декларация нулевого или отрицательного лимита не компилируется.
Multipart, form data и streaming response пока не входят в API.

## URI и query

Backend передаёт path capture и query value в codec после однократного
percent-decoding. Для scalar query-параметров повторный ключ возвращает 400
`Duplicate_parameter`, вместо выбора первого или последнего значения.
`arg` с array-схемой в query не компилируется: используйте `Query`.

`query_arg` принимает типизированный `Query.t`; `/!` задаёт обязательный
параметр, `/?` — необязательный. В path-параметрах `query_arg` недоступен.
`Query.csv` разбивает одно значение по запятой и публикует `style: form`,
`explode: false`; повторный CSV-ключ возвращает 400. `Query.repeated`
декодирует отдельные occurrences в wire order и публикует `explode: true`.
Значение с запятой внутри элемента представимо через repeated. CSV escaping
для запятой внутри элемента не поддерживается.

Отсутствующий обязательный параметр возвращает missing error; отсутствующий
необязательный даёт `None` без вызова decoder. Присутствующее пустое значение
передаётся decoder. `Query.v` получает список уже разделённых элементов и
`~schema` того же OCaml list type. Ошибки элементов проходят через обычную
endpoint/group/compile decode-error policy.

## Ошибки

`Decode_error` не включает исходное тело запроса, чтобы случайно не записать в
ответ или лог секреты. Встроенный `Decode_error_response.default` возвращает
JSON с полями `code` и `message` и также не отражает ошибочное исходное значение.
Диагностика JSON/parser decoder намеренно скрыта; подробный формат можно
включить только явной прикладной политикой.
Приложение может перевести ошибку в собственный JSON DTO через
`Decode_error_response.json`. Endpoint-политика имеет приоритет над групповой,
групповая — над переданной в `compile`, а встроенная используется последней.
Ошибки path/query/header параметров получают 400 до вызова handler. Для
`Request.json`, `Request.text` и `Request.binary` проверка `Content-Type`, чтение
тела и декодирование происходят только при `Request_body.read`. Результат
чтения кэшируется в рамках одного запроса. `Request_body.reject` применяет
текущую decode-error policy: ошибка JSON получает 400, превышение лимита — 413,
неподдерживаемый media type — 415. Если handler не вызывает `read`, тело
остаётся непрочитанным и эти ошибки не возникают. OpenAPI по-прежнему
документирует возможные ошибки тела.

## Описания ответов

`Response.json ~description:"Pet not found" (module Dto.Api_response)`
задаёт описание конкретного ответа. Без этого аргумента используется описание
схемы DTO: явно заданное через `Json_schema.with_openapi ~description`, затем
корневой JSON Schema `description`, затем пустая строка. Явно переданная пустая
строка сохраняется. Описание не заменяется стандартной HTTP reason phrase,
даже если оно общее, например `API response`. Локальный override не меняет схему, имя
компонента, headers или runtime-кодирование; он сохраняется при
`Response.with_header` и в ответах Guard.

Автоматические ошибки используют одну decode-error policy для нескольких
статусов. Их описания настраиваются отдельно от JSON mapping:

```ocaml
let decode_errors =
  Decode_error_response.json
    ~payload:(module Dto.Api_response)
    ~map:Dto.Api_response.of_decode_error
  |> Decode_error_response.with_description (function
    | `Bad_request -> Some "Invalid request"
    | `Request_entity_too_large -> Some "Request body too large"
    | `Unsupported_media_type -> Some "Unsupported media type"
    | _ -> None)
```

`None` сохраняет исходное описание policy, `Some ""` задаёт пустое описание.
Повторный вызов `with_description` заменяет предыдущий override; `None`
возвращает к исходному описанию, а не к предыдущей функции. Функция вызывается
при компиляции для достижимых автоматических статусов и должна быть чистой
и детерминированной. При обработке HTTP-запросов она не вызывается.
Статусы, JSON mapping и приоритет выбора policy endpoint → group → compile
остаются прежними.

Если явно объявленный и автоматический ответы имеют одинаковый статус,
их content и headers объединяются по существующим правилам, а описание
остаётся от явного ответа, включая пустую строку или fallback DTO. Таким
образом, настройка автоматического 400 не заменяет описание явного `case`.

## Типизированные request и response headers

`Header.required` и `Header.optional` связывают имя header, JSON Schema,
документацию, decoder и encoder. `header` разрешён после path/query и до
`documented`; его значение добавляется к curried аргументам handler в порядке
декларации. Поиск имени регистронезависим. Отсутствующий required header и
ошибка codec получают тот же настраиваемый decode-error response со статусом
400, что path/query.

`Response.with_header` добавляет header к конкретному response payload и
меняет его OCaml-тип на `(header, body)`. Optional header имеет тип
`'a option` и при `None` не отправляется. Для двух деклараций результат имеет
вид `(outer, (inner, body))`. OpenAPI получает `headers` с required,
description и schema из той же декларации.

Имена request/response headers проверяются как HTTP token во время `compile`.
Имена сравниваются регистронезависимо; повтор в одном response отклоняется.
Закодированное runtime-значение не может содержать CR, LF или другой запрещённый
control character: вместо отправки потенциально инъецированного ответа
выбрасывается `Runtime_error` без включения самого значения в diagnostic.
Исключение должно попасть во внешний application error boundary.

Request headers `Accept`, `Content-Type`, `Authorization` не могут быть typed
header parameters: representation задаётся payload, авторизация — `Security`
и `Guard`. Response headers `Content-Type`, `Content-Length`,
`Transfer-Encoding`, `Trailer`, `Connection` принадлежат payload/transport
и отклоняются при `compile`. Допустимый HTAB в response value сохраняется.

## OpenAPI

Оценка покрытия OpenAPI 3.1 и ограничения генератора приведены в
[Покрытие OpenAPI 3.1](openapi_coverage.md).

Payload-модули публикуют `t_jsonschema : t Json_schema.t`, где `t` — тип DTO.
Сгенерированных кодеков и схемы достаточно для request/response; отдельного
`Metadata.t` нет. `Json_schema.with_openapi` добавляет необязательные описание,
теги и имя компонента, сохраняя тип схемы. Источник схемы выбирается в следующем
порядке:

- DTO и его wire shape описываются `[@@deriving yojson, jsonschema]` с пакетом
  `typed-endpoint-ppx`; общие `@default`, `@key` и `@name` не дублируются
  schema-specific аннотациями;
- ограничения поля задаются
  типизированным ``[@jsonschema.format `Date_time]``, `[@jsonschema.minimum]`
  и аналогичными аннотациями;
- `[@jsonschema.title]` и `[@jsonschema.description]` документируют DTO, поля и
  варианты; `[@jsonschema.attrs]` принимает `title`, `description`, `format`,
  `minimum` и `maximum`;
- record schemas по умолчанию запрещают дополнительные поля; это можно явно
  зафиксировать атрибутами
  `[@@jsonschema.disallow_extra_fields]` или `[@jsonschema.disallow_extra_fields]`
  на constructor с inline record;
- standalone параметры, headers, enum, массивы и dictionaries собираются
  конструкторами `Json_schema`;
- внешние схемы и произвольные JSON Schema keywords импортируются через
  `Json_schema.Unsafe.of_yojson`. Мосты `ppx_schema`, `to_ppx` и `Unsafe.of_ppx`
  удалены.

`Json_schema.Unsafe` — явно небезопасный мост для внешнего представления или
keyword, которого ещё нет в DSL. Не используйте его для постобработки
сгенерированной схемы: такая правка расходится с типом DTO и легко ломается при
обновлении PPX. Конструкторы без `_exn` проверяют противоречивые bounds,
отрицательные длины, пустые format/enum, дубликаты enum и default вне
объявленного диапазона. Стандартный format в DSL задаётся типизированным
вариантом, например `` `Date_time``, `` `Int64`` или `` `Double``. PPX использует
те же категории и синтаксис, включая ``[@jsonschema.format (`Custom "my-format")]``.
`Custom` в PPX требует непустой строковый литерал; категория определяется по
wire type, включая `option` и строковое кодирование целого. Аннотации не
добавляют runtime-валидацию формата или других ограничений в Yojson-кодек.
Например, `[@jsonschema.minimum 0]` само по себе не запрещает декодировать
отрицательный `int`. Гарантии генерации, нормализации и runtime, тестовые
сценарии и проверка JS-чисел описаны в
[проверке соответствия контракту](contract_conformance.md).

Повторение keyword на одном узле, в том числе в `jsonschema.attrs`, отклоняется;
аннотации внешнего узла могут переопределять вложенную схему. При наличии
Yojson-декодера явные `jsonschema.strict` и `allow/disallow_extra_fields` должны
совпадать с его политикой. Без декодера локальные атрибуты переопределяют
`jsonschema.strict`, по умолчанию дополнительные поля запрещены, в том числе
у DTO только с `to_yojson` и inline-записей вариантов.
`compact_variants`, `polymorphic_variant_tuple` и строковый `jsonschema.ref`
удалены: форма вариантов всегда соответствует массивам Yojson, а custom scalar
получает типизированную `<type>_jsonschema`.

Для необязательного record field используйте общий `@default`, например
`[@default None]`, на поле или внутри его типа, в том числе для option aliases.
Общие аннотации `key`, `name`, `default` и `encoding` поддерживают префиксы
`yojson.*` и `deriving.yojson.*`; старые `jsonschema.key`, `jsonschema.name`,
`jsonschema.default` и `jsonschema.option` отклоняются с подсказкой замены.
Строковое кодирование `int64`/`nativeint` через ``[@encoding `string]``
учитывается и при сериализации `default`; числовые ограничения на таком типе
отклоняются. PPX генерирует URN из namespace и позиции объявления, без
пути к checkout. Корневой `$id` рекурсивной схемы сохраняется при встраивании
в OpenAPI, а `Json_schema.nullable` сохраняет ограничения `enum` и `const`.

Тесты библиотеки сравнивают схемы smart constructors с PPX структурно, не
учитывая порядок полей JSON object. Все standalone и встроенные в Petstore
OpenAPI schema fragments дополнительно проверяются Draft 2020-12
meta-schema-валидатором. Валидатор остаётся test dependency и не попадает в
runtime ядра.

`Json_schema.with_openapi ~schema_name` включает components и `$ref`. При рендеринге вложенные
структурные копии уже зарегистрированных объектных моделей тоже заменяются
ссылками. Анонимные примитивы и стандартные коллекции остаются inline, даже
если есть структурно равный именованный scalar/collection component; ссылки
на DTO внутри коллекций сохраняются. Явный `schema_name` всегда учитывается.
Новые имена для анонимных схем не создаются. Явно выбранные имена сохраняются;
при равных кандидатах для анонимного вхождения выбирается лексикографически
первое имя. Дедупликация учитывает ограничения и аннотации. Поддеревья с
`$id`, `$defs`, ссылками, anchors, собственным диалектом или неизвестными
keywords не переписываются. `default` и примеры не обходятся как схемы.

Все Response Objects остаются внутри операций вместе с description, headers
и content. Автоматические `components.responses` и имена с хешами не создаются;
режима Compact нет. Модели тела ответа по-прежнему используют именованные
`components.schemas`.

Если путь имеет несколько операций, полностью одинаковые path-параметры всех
операций объявляются один раз в `Path Item.parameters`. Сравнивается весь
Parameter Object, включая описание, схему и ограничения. Различающиеся параметры,
query и headers остаются у операций. При единственной операции подъёма нет.
Runtime и типы аргументов handler от этого преобразования не меняются.
Пустые `parameters` и `required` опускаются. Operation description опускается,
если он пустой или точно совпадает с summary; полезные отличия сохраняются.

Одинаковое имя с разными схемами, конфликтующие security schemes, неизвестные OAuth scopes, повторные
маршруты, operationId и response status являются ошибками `compile`. Маршруты
вида `/pets/:id` и `/pets/:name` также конфликтуют: их runtime-shape совпадает,
даже если имена capture различаются. В одном endpoint нельзя повторять имя
path-, query- или header-параметра, а явный status должен лежать в диапазоне
200--599. Промежуточные 1xx нельзя объявлять финальным результатом handler;
204, 205 и 304 требуют пустого payload.
При допустимом пересечении `/pets/find` имеет приоритет над `/pets/:id`
независимо от порядка объявления; маршруты одинаковой специфичности сохраняют
исходный порядок.
Prefix группы принимает только непустые статические сегменты без `/`,
dot-navigation и начальных `:` или `*`. Typed route не принимает
wildcard-синтаксис; список отрендеренных `:capture` сверяется со списком
типизированных path-параметров.
Capture names допускают ASCII letters, digits, underscore и непустые части,
разделённые точками. Статические сегменты и group prefixes отклоняют пробелы,
controls, `?`, `#` и невалидные percent escapes. Статические braces экранируются
в OpenAPI и `Route_info`, сохраняя отличие от captures.
Корневой route внутри prefix нормализуется в `/v1`, а не `/v1/`.
Перед публикацией документа задайте `Openapi.Config` с title, version,
description и servers.

Имена API-key headers проверяются как HTTP field-name, повторяющиеся OAuth
scopes отклоняются. OAuth authorization URL проверяется как абсолютный
HTTP(S) URI: authority, IPv6/IPvFuture literals, path и query должны
соответствовать RFC 3986. Пробелы, controls и символы вроде `<` или `>`
требуют percent encoding. Fragment запрещён для authorization endpoint по
RFC 6749; encoded `%23` в path/query допустим. Ошибка обнаруживается во время
`compile`; DNS и доступность сервера не проверяются.

`Backend.S.respond_json` принимает необязательный `?pretty:bool` с default
`false`. Собственные backend adapters должны добавить этот аргумент:
при `true` сериализовать через `Yojson.Safe.pretty_to_string`, иначе через
`Yojson.Safe.to_string`. Content-Type и JSON-значение не меняются.
Petstore включает отступы только для `/openapi.json`; остальные ответы API
сохраняют компактное представление.

Backend возвращает текст с `Content-Type: text/plain; charset=utf-8`, HTML с
`text/html; charset=utf-8`, JSON с `application/json`, а body-less response без
`Content-Type`. Встроенные роутеры Dream, Eio и testing добавляют `Allow` к
ответу 405; Opium adapter обеспечивает ту же семантику одним mount-level
middleware.

Capability `Response.case` статически связывает status и payload с веткой
handler. Capability можно сохранить вне handler, поэтому перед рендерингом
runtime дополнительно сверяет её непрозрачный identity со списком cases этого
endpoint. Чужая capability получает `Runtime_error` и не рендерится.

## Opium mount и постепенная миграция

Opium `app_builder` является immutable-коллекцией маршрутов, а не функцией
`App.t -> App.t`. Приложение вызывает
`Typed_endpoint_opium.mount (Compiled.app compiled) app` один раз. Mount
регистрирует все routes и один общий middleware для 405/`Allow`; количество
middleware больше не растёт с количеством endpoint.

Существующее Opium приложение можно мигрировать по одному endpoint: старые
routes остаются в `app`, новые собираются typed-endpoint и монтируются рядом.
Typed mount не запускает сервер, не меняет port/TLS и не владеет middleware
lifecycle. Если приложение компилирует несколько независимых route collection,
каждую можно mount отдельно, но предпочтительно объединить их одним `compile`.
Практические шаги переноса и пример подключения описаны в
[руководстве по миграции с Opium](opium_migration.md).

## Исключения и cancellation

Ядро намеренно не превращает произвольное исключение handler в не объявленный
500: такой ответ расходился бы с типизированными responses и OpenAPI. Внешний
framework middleware является последней границей для logging и generic 500.
Route-aware interceptor можно использовать для timing и записи ошибки вместе с
`Route_info`, после чего исключение следует пробросить дальше.

В Lwt middleware не перехватывайте `Lwt.Canceled` как application error. В Eio
не используйте безусловный `with _` вокруг request: cancellation и shutdown
должны дойти до runtime. Текст generic 500 не должен включать exception,
request body, Authorization, Cookie или raw query. Ожидаемые domain failures
возвращаются только объявленными response constructors.

Timeout, CORS, compression, trusted-proxy policy и request ID остаются внешними
framework middleware. Это сохраняет typed-endpoint библиотекой: она не владеет
server lifecycle и не вводит собственный application runtime.

## Тестирование

`typed-endpoint-testing` исполняет `Compiled.app` напрямую и не запускает web
framework или сокет. Основную бизнес-семантику проверяйте через него, а в
adapter tests оставляйте преобразование request/response и router integration.
`Typed_endpoint_testing.Client.call` объединяет создание request и dispatch, а
`Typed_endpoint_testing.Response.header` выполняет регистронезависимый поиск
заголовка.

`Typed_endpoint_testing.Backend_conformance` задаёт единый black-box suite для
всех backend: bounded body, response representations, typed и raw
case-insensitive headers, duplicate scalar query, 404/405 с `Allow`, статический
приоритет, escaped static segments, однократный decode path capture,
конкретные JSON media types, decode errors и порядок
`Backend.S.combine`. Каждый adapter test предоставляет только harness для
создания request и чтения response. Прохождение suite является обязательной
частью готовности нового backend.

Отдельно проверяйте wire contract без повторного использования application
codec в setup и assertions. В Petstore такой тест отправляет literal JSON и
проверяет сырой status, headers, content type, body и имена полей через
независимый разбор `Yojson.Safe`. Это ловит симметричные ошибки encoder/decoder,
которые не видны при round trip одним codec.

Property tests на QCheck дополнительно генерируют percent-encoded path segments,
повторные scalar query, разные регистры header names и порядок объявления
пересекающихся static/capture routes. Негейтящий benchmark router запускается
отдельно:

```sh
opam exec -- dune exec benchmark/router_bench.exe -- 1000 100000
```

Benchmark нужен для сравнения изменений на одном окружении; абсолютное время не
является test threshold. Opium adapter test отдельно проверяет структурный
инвариант: один mount добавляет ровно один middleware независимо от route count.

## Поддержка и release gate

Ядро, PPX, testing backend, Opium и Cohttp/Lwt adapters поддерживают OCaml >= 4.14.1;
Petstore с Opium или Cohttp/Lwt также собирается на 4.14.1. Dream и Eio adapters требуют
OCaml >= 5.1.1. Eio adapter сохраняет `cohttp-eio 6.3.0` и требует
`eio >= 1.2`. Версия конкретного adapter меняется отдельной migration с
повторным запуском общего conformance suite. Ядро не обещает совместимость с
framework API вне соответствующего adapter package.

### Проверка OCaml 4.14.1

Используйте отдельный switch и выбирайте только пакеты, поддерживающие 4.14.1.
При сборке компилятора из исходников с GCC 15 задайте режим C11 через `CC`.
Собирайте в отдельном build directory, чтобы не смешивать артефакты разных
компиляторов. Не копируйте готовый switch: его конфигурация может сохранить
пути к старому окружению.

```sh
CC='gcc -std=gnu11' opam switch create /tmp/typed-endpoint-ocaml-4.14.1 ocaml-base-compiler.4.14.1
opam install --switch=/tmp/typed-endpoint-ocaml-4.14.1 --deps-only --with-test ./typed-endpoint.opam ./typed-endpoint-ppx.opam ./typed-endpoint-testing.opam ./typed-endpoint-opium.opam ./typed-endpoint-cohttp-lwt.opam
opam exec --switch=/tmp/typed-endpoint-ocaml-4.14.1 -- dune build --root . --build-dir /tmp/typed-endpoint-build414 --only-packages typed-endpoint,typed-endpoint-ppx,typed-endpoint-opium,typed-endpoint-cohttp-lwt,typed-endpoint-testing @install @runtest examples/petstore/servers/opium_server.exe examples/petstore/servers/cohttp_lwt_server.exe
```

На Ubuntu транзитивным TLS-зависимостям Opium нужен `libgmp-dev`; Dream также
может потребовать `libev-dev` и `libssl-dev`.

### Подготовка релиза

Перед тегом выполняется `make release-check`: форматирование, build, tests,
package smoke tests, install targets, opam lint и проверка whitespace.
Эта цель уже включает `make check`, поэтому отдельно повторять её не нужно:

```sh
make release-check
make release-artifacts
make release-install-check
```

`make release-artifacts` создаёт в `_release` source archive, SHA-256 и
заготовки семи пакетов для opam-repository с источником из Git-тега.
Релиз публикуется созданием и отправкой Git-тега `v<version>`; GitHub Release
не создаётся. SHA-256 относится к локальному source archive.
`make release-install-check`
распаковывает archive и проверяет install targets, тесты и внешние
consumer-проекты в активном switch OCaml >= 5.1.1; отдельный compiler
не устанавливается. Распакованный исходный код остаётся в `_release` для
проверки. Изменения публичного API фиксируются в `CHANGES.md`. Правила private security reporting описаны в `SECURITY.md`.

Разделение чистого контракта и server handler, а также сетевой typed client
сознательно отложены. Текущий production-hardening не вводит параллельный DSL и
не меняет ownership приложения.
