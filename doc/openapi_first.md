# OpenAPI-first: DTO, сервер и версии экспорта

Пакет `typed-endpoint-openapi` генерирует HTTP-слой из одного или нескольких заранее
дереференсированных JSON OpenAPI **3.0.3** или **3.2.1**. Декларация маршрута для runtime
и OpenAPI создаётся генератором; доменные типы, сервисы, обработчики и маппинги
DTO остаются рукописными. Версия экспорта выбирается независимо от входа.

## Подключение через Dune

В библиотеке приложения нужны `base`, `yojson`, `typed-endpoint`, а для
препроцессинга — `ppx_let`, `ppx_deriving_yojson` и `typed-endpoint-ppx`.
Для форматирования generated-файлов при сборке нужен `ocamlformat` той версии,
которая указана в `.ocamlformat` проекта.
Генератор используется при сборке и не нужен сгенерированному коду в runtime.
Правило генерации и библиотека находятся в `generated/dune`:

```lisp
(rule
 (mode (promote (until-clean)))
 (targets support.ml support.mli dto.ml dto.mli
          operations.ml operations.mli server.ml server.mli)
 (deps ../openapi.json ../config.json ../../../.ocamlformat)
 (action
  (progn
   (run %{bin:typed-endpoint-openapi} generate
    --input %{dep:../openapi.json}
    --config %{dep:../config.json}
    --output-dir .)
   (run %{bin:ocamlformat} --inplace %{targets}))))

(library
 (name generated_api)
 (modules support dto operations server)
 (libraries base yojson typed-endpoint)
 (preprocess (pps ppx_let ppx_deriving_yojson typed-endpoint-ppx)))
```

При сборке Dune копирует результат из `_build` в отдельную папку `generated/`
благодаря `(mode (promote (until-clean)))`: IDE может открывать сгенерированные модули.
Перед `promote` правило форматирует все восемь файлов через `ocamlformat`
с настройками проектного `.ocamlformat`. Этот файл указан в `deps`, поэтому
изменение правил форматирования обновляет generated-код. Он участвует
в общей проверке `make fmt`. `dune clean` удаляет эти копии; они исключены из Git.
CLI можно запускать отдельно; каталог `--output-dir` должен существовать.
Он записывает только восемь фиксированных
файлов после успешного разбора и проверки входа. При ошибке входа выдаётся
диагностика, generated-файлы не записываются.

Рабочий пример: [контракт](../examples/openapi/openapi.json),
[конфигурация](../examples/openapi/config.json),
[правило Dune](../examples/openapi/generated/dune) и
[привязка с HTTP-проверками](../examples/openapi/integration_test.ml).

## Отдельный контракт для каждой группы

Несколько файлов нужно передать в **один запуск** генератора, чтобы он построил
общий `Dto` и проверил согласованность типов. `--group-input GROUP=FILE` задаёт
имя группы явно; URL из файла остаются абсолютными и не получают новый префикс.
Пример правила в `generated/dune`:

```lisp
(rule
 (mode (promote (until-clean)))
 (targets support.ml support.mli dto.ml dto.mli
          operations.ml operations.mli server.ml server.mli)
 (deps ../catalog.json ../admin.json ../config.json ../../../.ocamlformat)
 (action
  (progn
   (run %{bin:typed-endpoint-openapi} generate
    --group-input Catalog=%{dep:../catalog.json}
    --group-input Admin=%{dep:../admin.json}
    --config %{dep:../config.json}
    --output-dir .)
   (run %{bin:ocamlformat} --inplace %{targets}))))
```

Получатся `Server.Make(B).Catalog` и `Server.Make(B).Admin`. При одинаковом
значении `naming.schema_identity` схемы используют один тип, например
`Dto.Pet.t`, в запросах и ответах обеих групп. Определения проверяются после
удаления выбранных метаданных и нормализации диалекта: `nullable: true` в 3.0.3
совместим с `type: ["string", "null"]` в 3.2.1. Это структурное сравнение
нормализованных схем, а не доказательство эквивалентности произвольной JSON Schema.
Совпадение одного имени не объединяет DTO. Несовместимые схемы с общей
идентичностью, дубли маршрутов и `operationId` возвращают ошибку.

Повторяемый `--input FILE` оставляет автоматическое разделение по URL.
Его имя источника — basename файла; для `--group-input` — имя группы.
Имена источников должны быть уникальными и стабильными: они участвуют
в идентичности анонимных схем и диагностике. Порядок аргументов не меняет
результат: источники сортируются по имени. При отсутствии выбранного
идентификатора схемы остаются локальными для документа.

Библиотечный API предоставляет тот же режим:

```ocaml
Typed_endpoint_openapi.generate_sources ~config
  [ { name = "catalog"; group = Some "Catalog"; document = catalog_json }
  ; { name = "admin"; group = Some "Admin"; document = admin_json }
  ]
```

`Server.openapi_config` использует `info` и `servers` первого источника
в порядке сортировки. У каждой группы есть собственный `openapi_config`
из первого источника этой группы; его можно передать при экспорте отдельно
скомпилированной группы. Для общего документа приложения можно передать
собственный `Openapi.Config.t`.

Рабочий пример со смешанными версиями и общим DTO:
[examples/openapi-groups](../examples/openapi-groups/generated/dune).

## Именование и идентичность

Необязательный `config.json` описывает извлечение строк из каждого объекта
схемы. Например, имя можно брать из `title`, а идентификатор из собственного
поля метаданных:

```json
{
  "naming": {
    "type_name": { "select": "/title" },
    "schema_identity": { "select": "/x-model-id" }
  }
}
```

`select` — JSON Pointer относительно текущей схемы. Преобразование
`json_pointer_last_segment` извлекает последний декодированный сегмент
выбранного указателя; без `transform` строка используется целиком.
Имена полей не зашиты в генератор. Конфигурация может выбирать элемент
массива, как показано в [ADR 0002](adr/0002-openapi-first-codegen.md).
Нестандартные поля метаданных, выбранные настройками, отделяются от схемы;
стандартные поля вроде `title` сохраняют семантику.

Без конфигурации или при отсутствии выбранного поля используется место
схемы: HTTP-метод, путь, request/response и вложенное свойство. Некорректное
значение или селектор не скрываются fallback. Совпавшие нормализованные
имена получают стабильный digest-суффикс. Имена, конфликтующие со служебными
модулями, также получают суффикс. Повторная идентичность даёт общий
DTO после проверки согласованности определений; одинаковое имя не объединяет
типы автоматически.

## DTO и обработчики

`Dto` содержит именованные типы с codecs и `t_jsonschema`. `Operations`
содержит модули операций: `Request.t`, `Response_200.t` и другие payload,
а также закрытый `Response.t` с конструкторами `Status_200`, `Status_400`
и т. д. Если ответ содержит headers, его payload — record с `body` и
полями `header_*`. Параметры request record имеют префиксы `path_`, `query_`
и `header_`, чтобы не смешивать одинаковые имена разных locations.

В `Server.Make (B)` находятся `Endpoint` и группы по первому статическому
сегменту пути. Группа предоставляет `Handlers.t`, `Decode_errors.t` и
`groups ~context ~decode_errors handlers`. Все обработчики обязательны,
используют `B.io` и получают значение типизированного контекста. Не нужно
второй раз перечислять runtime-маршруты.

Группа — только организация кода: `/api/v1/pets` относится к `Api`, путь
остаётся `/api/v1/pets`. Для `/` или пути без статических сегментов применяется
`Default`. Явная группа из `--group-input` имеет приоритет. `operationId` задаёт основу имени операции; без него используется
метод и путь.

Сервис принимает доменные типы. Пример сохраняет маппинг в
[Pet_mapping](../examples/openapi/pet_mapping.ml), контроллер — в
[Pet_controller](../examples/openapi/pet_controller.ml). Генератор эти файлы
не перезаписывает.

Необязательное non-nullable поле представлено `option`; необязательное
nullable поле — `Support.presence` с `Absent` и `Present`, внутри которого
`None` означает явный `null`. Обязательное nullable поле использует `option`,
но отсутствие ключа считается ошибкой. Defaults не подставляются.
Поддерживаются строковые enums с закрытыми вариантами OCaml.
`integer` представлен `int64`, `number` — конечным `float`; строковые форматы
остаются строками. Представление чисел ограничено этими OCaml-типами.

Объекты сохраняют дополнительные свойства согласно `additionalProperties`.
`oneOf` поддерживается для объектных веток с обязательным discriminator,
имеющим разные singleton string enums или строковые `const` в 3.2.1. Объектные `allOf` принимаются только
при согласованных свойствах и политике дополнительных полей. Для особых
представлений используются обычные сгенерированные codecs и импортированная
типизированная схема; подходящие представления используют существующие PPX.

## Автоматические ошибки

Контракт должен объявлять все достижимые автоматические статусы: 400 при
fallible параметрах/body, 413 и 415 при JSON body. Иначе генерация возвращает
ошибку. `Decode_errors.t` требует для каждой операции и статуса функцию
`Typed_endpoint.Decode_error.t → соответствующий Response_*.t`, включая
response headers, если они объявлены.

В ядре `Decode_error_response.case ~response ~map` связывает тип payload
с его mapper, а `by_status ~bad_request ~request_entity_too_large
~unsupported_media_type` выбирает case. Прежние `json`, `default`,
`with_description` и приоритет endpoint → group → compile сохранены.
В OpenAPI публикуются только достижимые статусы.

## Экспорт

`Compiled.openapi` по-прежнему выдаёт 3.1.0. Новый API независимо выбирает
целевую версию; `Openapi.Config.version` остаётся прикладным `info.version`:

```ocaml
open! Base

let export compiled =
  Endpoint.Compiled.export_openapi
    ~spec_version:Typed_endpoint.Openapi.Spec_version.V3_0_3
    compiled
;;
```

Результат — `Ok document` либо `Error` со списком `Openapi.Export_error.t`
(`path`, `message`). Доступны `V3_0_3`, `V3_1_0` и `V3_2_1`.
`V3_1_0` возвращает тот же документ, что `Compiled.openapi`. `V3_2_1` сохраняет
JSON Schema 2020-12 и публикует документ версии 3.2.1.

Экспорт 3.0.3 преобразует nullable, const/enum, exclusive bounds и локальные
определения/ссылки. Siblings `$ref` выражаются пересечением, примеры и defaults
не обходятся как схемы. Неподдерживаемые keywords, неоднозначные преобразования
границ или непредставимые конструкции дают ошибку, а не ослабленный контракт.
Экспорт не обещает преобразования произвольной JSON Schema 2020-12.

## Вход OpenAPI 3.2.1

Схемы разбираются по JSON Schema 2020-12 согласно
[спецификации 3.2.1](https://spec.openapis.org/oas/v3.2.1.html#schema-object).
Поддерживаются `type: [T, "null"]` с одним non-null типом, `type: "null"`
(OCaml `unit`, JSON `null`), строковый `const`, числовые `exclusiveMinimum`
и `exclusiveMaximum`, `examples` и boolean schema `true` (произвольный JSON).
Обязательные и необязательные nullable-поля сохраняют прежнее представление.
`nullable` из 3.0.3 в документе 3.2.1 отклоняется: нужно использовать null union.

Для `jsonSchemaDialect` и `$schema` принимаются стандартный диалект OAS
`https://spec.openapis.org/oas/3.2/dialect/2026-02-26` и
`https://json-schema.org/draft/2020-12/schema`; неизвестный диалект отклоняется.
Boolean schema `false`, несколько non-null типов, нестроковые non-null `const`,
динамические ссылки и неподдерживаемые JSON Schema keywords возвращают диагностику.
Новые возможности HTTP 3.2.1 — `querystring`, streaming `itemSchema`,
`additionalOperations`, discriminator `defaultMapping` и webhooks — пока
не генерируются и отклоняются при использовании в операциях.

## Границы первой версии

Поддерживаются GET/POST/PUT/PATCH/DELETE, scalar path/query/header,
query-массивы `form` с CSV или repeated encoding, одна `application/json`
representation, обязательное JSON body, JSON/пустые ответы и конкретные
финальные статусы. Поддержка ограничений в схемах не добавляет runtime-
валидацию `minimum`, `pattern` и подобных аннотаций.

Оставшиеся `$ref`, рекурсивные схемы, `readOnly`/`writeOnly` projections,
optional request body, альтернативные representations, default/range
responses, произвольные `anyOf` и неподдерживаемые композиции отклоняются.
Авторизация отложена: непустая эффективная `security` вызывает ошибку,
операционное `security: []` учитывается. Генератор не снимает защиту молча.

Проверки примеров: `opam exec -- dune runtest examples/openapi examples/openapi-groups`.
