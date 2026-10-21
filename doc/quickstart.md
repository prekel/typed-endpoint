# Быстрый старт

Создайте backend и откройте его DSL:

```ocaml
open Typed_endpoint
module Endpoint = Typed_endpoint.Make (Typed_endpoint_testing)
module Io = Endpoint.Io
open Io.Let_syntax
open Endpoint
```

JSON-модуль реализует `Request_payload.S` и/или `Response_payload.S`, а DTO для
обоих направлений — общую сигнатуру `Json_payload.S`. Достаточно сгенерированных
кодеков и `t_jsonschema`; отдельного значения метаданных нет:

```ocaml
module Pet = struct
  type t = { name : string } [@@deriving yojson, jsonschema]
end
```

При необходимости добавьте имя OpenAPI-компонента, описание и теги к схеме:

```ocaml
let t_jsonschema =
  Json_schema.with_openapi
    ~schema_name:"Pet"
    ~description:"A pet"
    ~tags:[ "pets" ]
    t_jsonschema
;;
```

Второй фрагмент размещается внутри DTO-модуля после объявления типа.
`with_openapi` возвращает новую схему того же OCaml-типа и сохраняет поля,
которые не переданы. Эти настройки не меняют JSON Schema и wire shape.
Описание по умолчанию берётся из корневого `[@@jsonschema.description]`,
а при его отсутствии равно пустой строке. `schema_name` необязателен; он
переносит схему в OpenAPI components.

`Json_schema.t` скрывает представление схемы от публичного HTTP API и
параметризован типом DTO. Для DTO подключите пакет `typed-endpoint-ppx` в Dune
через `(pps ppx_deriving_yojson typed-endpoint-ppx)` и используйте
`[@@deriving yojson, jsonschema]`. Полученный `t_jsonschema` передаётся
напрямую. Общие аннотации codec являются приоритетными: например,
поле `name : string option [@key "displayName"] [@default None]` одновременно
задаёт wire key, отсутствие поля по умолчанию и соответствующую PPX-схему.
Аннотации `jsonschema.key`, `jsonschema.name`, `jsonschema.default` и
`jsonschema.option` удалены: используйте общие `key`, `name` и `default`.
Поддерживаются также префиксы `yojson.*` и `deriving.yojson.*`.
При совместном выводе с Yojson схема повторяет его `strict`: по умолчанию
дополнительные поля запрещены, а `yojson { strict = false }` разрешает их.
Явные `jsonschema.strict` и `allow/disallow_extra_fields` при наличии декодера
должны совпадать с его настройками, иначе PPX выдаёт ошибку.
Без Yojson-декодера схема записи тоже запрещает дополнительные поля по умолчанию,
включая DTO только с `to_yojson` и inline-записи вариантов;
локальные `allow/disallow_extra_fields` переопределяют `jsonschema.strict`.
Чтобы запретить их явно, укажите `[@@jsonschema.disallow_extra_fields]`;
для inline-записи внутри варианта задайте `[@jsonschema.disallow_extra_fields]` на конструкторе.
Внешние JSON-схемы импортируются через `Json_schema.Unsafe.of_yojson`.
Для аннотаций используйте `[@jsonschema.title "Pet"]` и
`[@jsonschema.description "A store pet"]`. Те же `title` и `description` можно
задать одним атрибутом `[@jsonschema.attrs { title = "Pet"; description = "A store pet" }]`.
Атрибут `[@jsonschema.attrs]` также принимает типизированные по DTO `format`,
`minimum` и `maximum`, где это применимо. `format` принимает вариант:

```ocaml
type t =
  { date : string option [@jsonschema.format `Date_time]
  ; identifier : string [@jsonschema.format (`Custom "my-format")]
  ; count : int [@jsonschema.attrs { format = `Int32; minimum = 0 }]
  ; amount : float [@jsonschema.format `Double]
  }
[@@deriving yojson, jsonschema]
```

Форматы строки, целого и дробного числа берутся из соответствующих типов
`Json_schema.string_format`, `integer_format` и `number_format`. Для `option`
используется категория вложенного типа; целое с ``[@encoding `string]`` имеет
строковую категорию. `Custom` требует непустой строковый литерал. Старые
строки вроде `[@jsonschema.format "date-time"]` больше не поддерживаются.
Аннотацию `format` на пользовательском alias замените его типизированной схемой.

На одном узле нельзя повторять keyword, в том числе между отдельным атрибутом
и `jsonschema.attrs`; внешняя аннотация может переопределять вложенную.
Конструкторы вариантов всегда описываются массивами Yojson, включая `["Empty"]`.
Непосредственный tuple в polymorphic variant разворачивается: `["Pair", 1, "x"]`;
tuple через alias остаётся вложенным массивом. `compact_variants`,
`polymorphic_variant_tuple` и строковый `jsonschema.ref` удалены.

Схему значения без DTO можно собрать безопасными конструкторами:

```ocaml
let page =
  Parameter.v
    ~schema:(Json_schema.integer ~format:`Int32 ~minimum:1 ~maximum:100 ~default:1 ())
    ~description:"One-based page number"
    ~of_string:parse_page
    ()
;;
```

Конструкторы `Json_schema` возвращают схему напрямую и не имеют суффикса `_exn`.
Некорректная декларация поднимает `Json_schema.Invalid_schema`; зарегистрированный
принтер выводит публичное имя исключения и причину ошибки. Для
custom scalar экспортируйте типизированную схему как `t_jsonschema`. Мосты
`ppx_schema`, `to_ppx` и `Unsafe.of_ppx` удалены.
Известные форматы типизированы: используйте ``~format:`Date_time``,
``~format:`Int64`` или ``~format:`Double``. Нестандартное расширение записывается
явно как ``~format:(`Custom "vendor-format")``.

Для массивов query используются `/! query_arg` или `/? query_arg` и `Query.t`.
`Query.csv ~description (module Item)` принимает одно CSV-значение и
публикует `style: form`, `explode: false`. `Query.repeated` принимает повторные
ключи и публикует `explode: true`. `Item` реализует `Parameter.S` для одного
элемента; результат обоих codecs — список элементов. `Query.v` задаёт
собственную обработку списка с аргументом `~schema` того же OCaml list type. Scalar `arg` с
array-схемой в query отклоняется. Для CSV-элементов с запятыми используйте
repeated; CSV escaping не поддерживается.

`Compiled.openapi` выводит вложенные копии именованных объектных моделей через
`$ref`, а Response Objects оставляет inline. Одинаковые path-параметры всех
операций пути поднимаются в Path Item. Анонимные примитивы и коллекции остаются
inline; явно заданные имена схем сохраняются. Схемы с локальными ресурсами и
ссылками, `default` и примеры не сокращаются.

Для локального описания используйте
`Response.json ~description:"Pet not found" (module Dto.Api_response)`.
Без аргумента сохраняется description DTO; пустая строка — явный override.
`Decode_error_response.with_description` задаёт описания автоматических ошибок
по статусу без изменения JSON mapping и runtime-ответов.

`Request.json`, `Request.text` и `Request.binary` передают handler значение
`'a Request_body.t`. Тело не читается и `Content-Type` не проверяется, пока
handler не вызовет `Request_body.read`. Первый вызов проверяет media type,
читает тело с лимитом `max_body_bytes` (по умолчанию 1 МиБ для JSON) и
возвращает `Result`; повторный вызов использует тот же результат. Например:

```ocaml
let%bind pet = Request_body.read pet_body in
match pet with
| Ok pet -> respond ok pet
| Error error -> Request_body.reject error
```

`Request_body.reject` выбирает 400, 413 или 415 и применяет безопасный
`Decode_error_response.default`. Ошибку можно изучить через
`Request_body.to_decode_error` или обработать в handler самостоятельно. Формат
автоматического ответа заменяется через `Decode_error_response.json` на endpoint,
группу или весь `compile`.

Для типовых path/query-параметров используйте готовые `Parameter.string`,
`Parameter.int`, `Parameter.int64`, `Parameter.float` и `Parameter.bool`.
`Parameter.v` создаёт локальный codec без отдельного именованного модуля.

## URI DSL

Результат `Typed_endpoint.Make` напрямую предоставляет URI-first DSL объявления
endpoint. Phantom phase
заставляет соблюдать порядок: path, затем query, headers, metadata, request,
responses и handler. После первого query type checker больше не принимает `/` и `/:`;
`accepts` и `returns` также нельзя переставить местами.

```ocaml
let get_pet =
  get
  / "pet"
  /: arg "petId" (Parameter.int64 ~description:"Pet ID" ())
  /? arg "verbose" (Parameter.bool ~description:"Verbose response" ())
  |> documented ~operation_id:"getPetById" ~summary:"Finds a pet"
  |> accepts Request.empty
  |> returns
       (case `OK (Response.json (module Pet))
        <|> case `Not_found (Response.json (module Api_response)))
  ==> fun pet_id verbose ok not_found () () ->
     match find_pet pet_id verbose with
     | Some pet -> respond ok pet
     | None -> respond not_found (Api_response.not_found pet_id)
;;
```

`/` добавляет static segment, `/:` — required path capture, `/?` — optional
query и `/!` — required query. Порядок операторов одновременно задаёт порядок
curried аргументов handler. `<|>` объединяет декларации для `returns`, после
чего handler получает response capabilities позиционно в том же порядке.
Каждая capability типизирована status и payload; `respond` принимает её и
значение ровно соответствующего payload-типа. Маршрут завершается `==>`,
а его контекст задаётся через `Group.make_with_context`. Handler получает
контекст после response capabilities и перед request body. Для маршрутов без
зависимостей используйте `Context.return ()`: аргумент контекста имеет тип `unit`.
Backend request не добавляется неявно: при необходимости передайте
`Context.request` в `Group.make_with_context`. `Dependency` и
`Guard` добавляют остальные typed context values. Несколько контекстов удобно
сводить операторами из `Context.Applicative_infix`; `Context.all` собирает
однородный список. При использовании `ppx_let` композицию можно писать через
`Context.Let_syntax` и `let%map ... and ...`.

```ocaml
let api =
  Group.make_with_context
    ~context:(Context.return ())
    ~description:"Pets"
    ` get_pet `
;;
```

Асинхронные handlers используют тот же `ppx_let` через `Io.Let_syntax`. Тип
`Io.t` совпадает с backend `io`: это `Lwt.t` для Dream и Opium и identity для
testing и Eio. Благодаря этому handler не вызывает backend-specific `bind` и
`return` напрямую.

После `compile` используйте `Compiled.app` для backend-приложения и
`Compiled.openapi` для документа. Полный пример находится в
`examples/petstore`.

`compile ~interceptors` принимает route-aware wrappers. Каждый wrapper
выполняется после совпадения route, получает `Route_info.t` и поэтому пишет
низкокардинальный template вроде `/pet/{petId}`, а не raw target. Framework
middleware по-прежнему отвечает за request ID, CORS, compression и timeout;
`Context`/`Guard` — за request-scoped typed значения и авторизацию.

## Типизированные headers

`Header.required` и `Header.optional` используют двунаправленный codec:
`of_string` декодирует request, `to_string` кодирует response. Готовые codecs
`Header.string`, `Header.int`, `Header.int64` и `Header.bool` покрывают обычные
scalar headers. Request headers добавляются после path/query через
`header` и становятся следующими аргументами handler.

```ocaml
let version = Header.required "X-Api-Version" (Header.int ~description:"API version" ())
let result = Header.required "X-Result" (Header.string ~description:"Result marker" ())

let route =
  get / "versioned"
  |> header version
  |> documented
  |> accepts Request.empty
  |> returns
       (case `OK (Response.text ~description:"Version" () |> Response.with_header result))
  ==> fun version ok () () -> respond ok ("accepted", Int.to_string version)
;;
```

`Response.with_header` меняет payload type на `(header, body)`. Несколько
headers образуют вложенные пары в порядке декларации. Имя проверяется при
`compile`, а CR, LF и другие запрещённые control characters в runtime-значении
отклоняются через `Runtime_error`, чтобы не допустить header injection. Та же
декларация попадает в OpenAPI.

`Accept`, `Content-Type` и `Authorization` нельзя объявлять request header
parameters; для них используйте payload и `Security`/`Guard`. Response headers
`Content-Type`, `Content-Length`, `Transfer-Encoding`, `Trailer`, `Connection`
управляются payload/transport и отклоняются при `compile`. Финальные response
statuses должны быть в диапазоне 200--599; 204, 205 и 304 требуют пустого тела.

В framework-free тесте request можно выполнить одной функцией:

```ocaml
let response = Typed_endpoint_testing.Client.call (Compiled.app compiled) `GET "/health"
```

## Конкретные JSON media types

`Request.json` по умолчанию принимает только `application/json`. Для vendor
JSON перечислите конкретные типы через `~media_types`; runtime и OpenAPI будут
использовать один список:

```ocaml
Request.json
  ~media_types:` "application/json"; "application/vnd.example+json" `
  (module Item)
```

Для отсутствующего option field в DTO используйте `[@default None]`.
`default` можно разместить на поле или внутри его типа. `option` без `default`
остаётся обязательным полем, допускающим `null`.
Для строкового представления `int64` и `nativeint` используйте
``[@encoding `string]``; схема и JSON-значение `default` будут строковыми.
