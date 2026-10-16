# typed-endpoint

`typed-endpoint` — типизированный DSL для HTTP API на OCaml. Одна декларация
задаёт runtime-маршрут, декодирование входных данных, допустимые ответы и
OpenAPI 3.1.

Проект разделён на независимые пакеты:

- `typed-endpoint` — framework-agnostic ядро;
- `typed-endpoint-ppx` — typed JSON Schema deriver с wire-аннотациями Yojson;
- `typed-endpoint-testing` — прямой in-memory backend для тестов без сервера;
- `typed-endpoint-opium` — интеграция с Opium >= 0.17.1 и < 0.19.0;
- `typed-endpoint-dream` — интеграция с Dream 1.0.0~alpha8;
- `typed-endpoint-eio` — direct-style интеграция с cohttp-eio 6.3.

Deriver `typed-endpoint-ppx` перенесён и адаптирован на основе
[ahrefs/ppx_deriving_jsonschema](https://github.com/ahrefs/ppx_deriving_jsonschema).
Если вместе с `jsonschema` выводится Yojson-декодер (`yojson` или `of_yojson`),
политика `additionalProperties` берётся из его `strict`, включая значение по
умолчанию Yojson (`true`). Поэтому `yojson { strict = false }` разрешает
дополнительные поля и в схеме. Настройка `jsonschema { strict = ... }`
используется самостоятельно, когда Yojson-декодер не выводится. При наличии
декодера явные настройки схемы должны совпадать с ним: противоречащие `strict`
и `allow/disallow_extra_fields` отклоняются. Без декодера локальные
`allow/disallow_extra_fields` переопределяют `jsonschema.strict`.

Аннотации `key`, `name`, `default` и `encoding` общие для Yojson и схемы;
поддерживаются также имена `yojson.*` и `deriving.yojson.*`. `default` на поле
или его типе делает поле необязательным. Для `int64` и `nativeint` аннотация
``[@encoding `string]`` задаёт строку в JSON и строковое значение `default`;
``[@encoding `number]`` сохраняет числовое представление.

Аннотации `jsonschema.key`, `jsonschema.name`, `jsonschema.default` и
`jsonschema.option` удалены. Используйте соответственно `[@key ...]`,
`[@name ...]`, `[@default ...]` и `[@default None]`. Числовые ограничения
`jsonschema.minimum`/`maximum` несовместимы со строковым кодированием числа.

`[@jsonschema.*]` задают декларативные ограничения: они не добавляют
runtime-валидацию в Yojson-декодер. Проверки в codec и обработчике остаются
ответственностью приложения. Границы гарантий и тесты описаны в
[проверке соответствия контракту](doc/contract_conformance.md).

Форматы задаются типизированными вариантами:

```ocaml
type t =
  { created_at : string [@jsonschema.format `Date_time]
  ; identifier : string [@jsonschema.format (`Custom "my-format")]
  ; count : int [@jsonschema.attrs { format = `Int32; minimum = 0 }]
  ; amount : float option [@jsonschema.format `Double]
  }
[@@deriving yojson, jsonschema]
```

Категория формата проверяется по JSON-типу; `Custom` принимает непустой
строковый литерал. Старый синтаксис `jsonschema.format "date-time"` удалён.
Повторное указание keyword на одном узле, в том числе через `jsonschema.attrs`,
считается ошибкой. Аннотации внешнего узла могут переопределять вложенные.
Варианты всегда используют массивы Yojson: `["Empty"]`, `["Value", 1]`.
Настройки `compact_variants`, `polymorphic_variant_tuple` и строковый
`jsonschema.ref` удалены; для custom scalar определяйте `<type>_jsonschema`.
Мосты `ppx_schema`, `to_ppx` и `Unsafe.of_ppx` удалены; внешние JSON-схемы
импортируются через `Json_schema.Unsafe.of_yojson`.

## Основные гарантии

- типы path/query/header становятся аргументами handler, а body передаётся
  как типизированный `Request_body.t` и читается по требованию;
- handler получает объявленные response capabilities позиционно; каждый из них
  типизирован HTTP-статусом и payload;
- при чтении JSON body ограничен по размеру (по умолчанию 1 МиБ), проверяется
  `Content-Type`, а ошибки через `Request_body.reject` получают статусы
  400/413/415;
- именованные схемы попадают в `components/schemas`, конфликт имён отклоняется;
- компиляция отклоняет неоднозначные route-shape, повторные параметры и
  финальные status-коды вне 200–599; ответы 204/205/304 требуют пустого тела;
- `Guard` одновременно задаёт runtime-проверку и OpenAPI security requirement;
- route-aware interceptors получают типизированный `Route_info` с шаблоном
  пути, tags и security, но без application service locator;
- результат OpenAPI детерминирован.

## Минимальная декларация

```ocaml
open! Base
open Typed_endpoint

module Endpoint = Make (Typed_endpoint_testing)

open Endpoint

let route =
  get / "health"
  |> documented ~operation_id:"health"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Health status" ()))
  ==> fun ok () () -> respond ok "ok"

let compiled =
  compile_exn
    [ Group.make_with_context
        ~description:"Service"
        ~context:(Context.return ())
        [ route ]
    ]
```

`Compiled.app compiled` возвращает значение конкретного backend, а
`Compiled.openapi compiled` — тот же контракт в OpenAPI. Промежуточные типы
staged DSL не позволяют добавить path segment после query, переставить request
и responses или забыть одну из стадий. Например, маршрут с path-параметром:

```ocaml
let get_pet =
  get
  / "pet"
  /: arg "petId" (Parameter.int64 ~description:"Pet ID" ())
  |> documented ~operation_id:"getPetById"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Pet ID" ()))
  ==> fun pet_id ok () () -> respond ok (Int64.to_string pet_id)
```

`/?` добавляет optional query, `/!` — required query, `header` —
required или optional typed header, функция `case` связывает status с codec,
`<|>` соединяет альтернативные responses, а `respond case value` формирует
типизированный ответ. `==>` завершает маршрут для `Group.make_with_context`.
Handler получает path/query/header-параметры слева направо, затем response
capabilities в порядке `returns`, значение контекста группы и request body.
Если зависимости не нужны, передайте `Context.return ()`. Сырой request можно
получить через `Context.request`. Ошибки декодирования по умолчанию получают
безопасный JSON `{ "code": ..., "message": ... }`, который можно заменить на
уровне endpoint, группы или всей компиляции.

Для query-массивов используйте `/! query_arg` или `/? query_arg` с
`Query.csv`/`Query.repeated`:

```ocaml
let tags = Query.csv ~description:"Pet tags" (Parameter.string ~description:"Tag" ())

let find =
  get / "search" /! query_arg "tags" tags
  |> documented
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Selected tags" ()))
  ==> fun tags ok () () -> respond ok (String.concat ~sep:"," tags)
```

CSV принимает `?tags=cat,dog`, repeated — `?tags=cat&tags=dog`.
OpenAPI выводит `style: form` и соответствующий `explode`. CSV не экранирует
запятую внутри элемента; для таких значений используйте repeated. `Query.v`
позволяет связать собственный decoder списка элементов с его типизированными
metadata. Scalar query-codec с явной array-схемой отклоняется при компиляции.

OpenAPI оптимизирован для чтения: именованные DTO переиспользуются через
`components.schemas`, а сами HTTP-ответы остаются внутри операций. Искусственные
response components с хешами не создаются. Анонимные примитивы и стандартные
коллекции остаются inline; элементы коллекций могут ссылаться на DTO.
Явные `schema_name` сохраняются и для scalar/collection codecs.
Одинаковые path-параметры всех операций пути поднимаются в Path Item.
Пустые `parameters` и `required`, пустые operation descriptions и description,
совпадающий с summary, опускаются. `default`, примеры, ограничения и области
ссылок сохраняются. У генератора один читаемый формат без режима Compact.

Описание конкретного JSON-ответа можно переопределить без изменения DTO:

```ocaml
Response.json ~description:"Pet not found" (module Dto.Api_response)
```

Без `~description` используется описание DTO; явно заданная пустая строка
сохраняется. Для автоматических ошибок есть
`Decode_error_response.with_description`: функция от статуса возвращает
`Some text` для override или `None` для исходного описания. Подробнее —
[описания ответов](doc/production.md#описания-ответов).

Для `Request.json`, `Request.text` и `Request.binary` последний аргумент
handler — `Request_body.t`. Вызов `Request_body.read` возвращает `Result` в
эффекте backend; `Request_body.reject` применяет настроенный ответ при ошибке.
Тело и `Content-Type` проверяются только при первом чтении.

`Request.json` по умолчанию принимает только `application/json`. Для vendor
JSON перечислите конкретные типы через
`~media_types:[ "application/json"; "application/vnd.example+json" ]`:
runtime и OpenAPI используют один список и один codec. Суффиксный wildcard
`application/*+json` не поддерживается.

Если один guard или набор зависимостей используется несколькими маршрутами,
контекст один раз прикрепляется через `Group.make_with_context`. Его тип
остаётся связан с handler каждого маршрута.

Interceptors передаются в `compile ~interceptors`. Они запускаются после
совпадения маршрута и подходят для tracing, metrics и access log по стабильному
`Route_info.path_template`. Request ID, CORS, compression и transport timeout
остаются framework middleware вокруг `Compiled.app`; авторизация и
request-scoped значения выражаются через `Guard`/`Context`.

Opium использует отдельный шаг mount: `Compiled.app` возвращает immutable
коллекцию typed routes, а `Typed_endpoint_opium.mount routes app` один раз
добавляет маршруты и общий 405/`Allow` middleware в существующее приложение.
Так старые Opium endpoint можно заменять по одному без передачи server lifecycle
библиотеке. Пошаговый процесс с примерами описан в
[руководстве по миграции с Opium](doc/opium_migration.md).

## Установка из GitHub

Все шесть пакетов находятся в одном репозитории и требуют одинаковую версию.
Скрипт ниже устанавливает текущий релиз `v0.3.1`, а если пакеты уже установлены —
обновляет их до этой версии, предварительно заменяя существующие pin.
Для установки всех пакетов нужен switch OCaml 5.1.1 или новее:

```bash
typed_endpoint_packages=(
  typed-endpoint
  typed-endpoint-ppx
  typed-endpoint-testing
  typed-endpoint-opium
  typed-endpoint-dream
  typed-endpoint-eio
)
for package in "${typed_endpoint_packages[@]}"; do
  opam pin add -yn "$package" 'git+https://github.com/prekel/typed-endpoint.git#v0.3.1'
done
opam install "${typed_endpoint_packages[@]}"
```

Если нужны только некоторые пакеты, оставьте в списке их имена и зависимости
из этого репозитория. Для первого сервера ниже достаточно `typed-endpoint`,
`typed-endpoint-ppx` и `typed-endpoint-opium`; они поддерживают OCaml 4.14.1.
При установке адаптеров с `--with-test` добавьте `typed-endpoint-testing`.

`-n` откладывает установку до общего `opam install`, а `-y`
подтверждает замену существующего pin. Тег указывается после `#` в Git URL.
Изменения API версии `v0.3.1` описаны в [истории изменений](CHANGES.md).

## Первый сервер

Создайте каталог приложения:

```sh
mkdir hello_typed_endpoint
cd hello_typed_endpoint
```

Минимальный `dune-project`:

```lisp
(lang dune 3.14)
(name hello_typed_endpoint)
```

В `dune` добавьте executable:

```lisp
(executable
 (name main)
 (libraries base yojson typed-endpoint typed-endpoint-opium)
 (preprocess
  (pps ppx_let ppx_deriving_yojson typed-endpoint-ppx)))
```

`main.ml` объявляет маршрут и подключает скомпилированные routes к
Opium-приложению:

```ocaml
open! Base
open Typed_endpoint

module Endpoint = Make (Typed_endpoint_opium)
module Io = Endpoint.Io

open Io.Let_syntax
open Endpoint

module Greeting = struct
  type t = { name : string } [@@deriving yojson, jsonschema]

  let metadata : t Metadata.t =
    Metadata.v ~schema:t_jsonschema ~description:"Name to greet" ()
  ;;
end

let route =
  post / "hello"
  |> documented ~operation_id:"sayHello"
  |> accepts (Request.json (module Greeting))
  |> returns
       (case `OK (Response.text ~description:"Greeting" ())
        <|> case `Unprocessable_entity (Response.text ~description:"Empty name" ()))
  ==> fun ok invalid () body ->
      let%bind result = Request_body.read body in
      match result with
      | Error error -> Request_body.reject error
      | Ok greeting when String.is_empty greeting.name ->
        respond invalid "name is required"
      | Ok greeting -> respond ok ("Hello, " ^ greeting.name)
;;

let routes =
  compile_exn
    [ Group.make_with_context
        ~description:"Hello"
        ~context:(Context.return ())
        [ route ]
    ]
  |> Compiled.app
;;

let () =
  Opium.App.empty
  |> Typed_endpoint_opium.mount routes
  |> Opium.App.port 8080
  |> Opium.App.run_command
;;
```

Запустите сервер:

```sh
dune exec ./main.exe
```

В другом терминале проверьте три варианта ответа:

```sh
curl -i -X POST http://127.0.0.1:8080/hello -H 'Content-Type: application/json' --data '{"name":"Ada"}'
curl -i -X POST http://127.0.0.1:8080/hello -H 'Content-Type: application/json' --data '{"name":""}'
curl -i -X POST http://127.0.0.1:8080/hello -H 'Content-Type: application/json' --data '{'
```

Первый запрос возвращает `200` и `Hello, Ada`, второй — объявленный `422`,
третий — автоматический JSON-ответ `400` для невалидного тела. Текстовые ответы
имеют `Content-Type: text/plain; charset=utf-8`.

Функция `case` статически связывает status и payload с конкретной веткой
handler. Capability другого endpoint может быть сохранена и передана в другой
handler, поэтому перед рендерингом библиотека дополнительно проверяет её
принадлежность объявленным cases и отвергает чужую capability с
`Runtime_error`.

## Petstore

В [examples/petstore](examples/petstore/README.md) находится расширенный пример
на основе Swagger Petstore v3: разделы `pet`, `store` и `user`,
бинарная загрузка изображений, отдельное пагинированное расширение,
HTTP Bearer/API-key guards, DI доменных сервисов, страница выбора Swagger UI, Scalar,
RapiDoc, Redoc и Stoplight Elements на `/docs`, `/openapi.json` и runtime-only
`/health`. Один DSL запускается через testing, Opium, Dream и Eio.

Login принимает обязательные credentials в JSON через `POST /user/login` и
создаёт сессию на один час; `POST /user/logout` отзывает её. Независимый demo
bearer сохранён как административный. Регистрация и чтение профиля публичны;
обновлять и удалять профиль может владелец либо административные credentials.
Создание требует username и password, PUT требует password и заменяет профиль;
смена пароля и удаление отзывают все сессии пользователя. Batch требует
административных credentials и возвращает массив. Ответы пользователя не содержат пароль. Эти и остальные
отличия от исходного Petstore описаны в README примера.

```sh
opam exec -- dune runtest examples/petstore/test
opam exec -- dune exec examples/petstore/servers/opium_server.exe
```

## Совместимость и ограничения

Требуется Dune 3.14 или новее. Собственным реализациям `Backend.S` нужно
поддержать `respond_json ?pretty` с default `false`; существующие вызовы
сохраняют компактное представление. Petstore использует `~pretty:true` только
для `/openapi.json`.

| Пакеты | Минимальный OCaml | Версии HTTP-библиотек |
| --- | --- | --- |
| `typed-endpoint`, `typed-endpoint-ppx`, `typed-endpoint-testing` | 4.14.1 | — |
| `typed-endpoint-opium` | 4.14.1 | Opium >= 0.17.1 и < 0.19.0 |
| `typed-endpoint-dream` | 5.1.1 | Dream 1.0.0~alpha8 |
| `typed-endpoint-eio` | 5.1.1 | cohttp-eio 6.3.0, Eio >= 1.2 |

Petstore с Opium также работает на OCaml 4.14.1. Один endpoint объявляет один
формат request body; для JSON можно перечислить несколько конкретных media
types с одним codec. Альтернативные форматы JSON/XML, multipart/form-data и
streaming responses не входят в API. Подробности — в
[руководстве по эксплуатации](doc/production.md).

## Разработка

Для полной локальной проверки в switch OCaml 5.1.1 или новее:

```sh
make deps_all
make check
```

`make check` включает форматирование, сборку, тесты, install targets и
проверку пакетов. Подготовка релиза и проверка OCaml 4.14.1 описаны в
[руководстве по эксплуатации](doc/production.md).

## Документация

- [Быстрый старт и DTO](doc/quickstart.md)
- [Архитектура](doc/architecture.md)
- [Эксплуатация и ограничения](doc/production.md)
- [Покрытие OpenAPI 3.1](doc/openapi_coverage.md)
- [Обзор документации](doc/index.md)
- [История изменений](CHANGES.md)
- [План развития](doc/roadmap.md)
- [Сообщение об уязвимости](SECURITY.md)
