# Преобразования Domain ↔ DTO

`typed-endpoint-mapper-ppx` автоматически выводит преобразования из рукописных
DTO через `mapper_from` / `mapper_into`. Для generated DTO и отдельных
преобразований остаются внешние `[%mapper]` / `[%mapper_result]`. `typed-endpoint-mapper` предоставляет чистые конвертеры и ошибки.
Оба пакета независимы от HTTP, Yojson, Lwt, базы данных и ядра typed-endpoint.
API первой версии экспериментальный.

Domain и application работают с доменными типами. HTTP-слой владеет DTO и
преобразованиями: code-first выводит функции в модуле DTO, contract-first
использует отдельный mapping-модуль. Controller вызывает их между decoder и
application service. Для проверки mapper не нужны сервер, Lwt и PostgreSQL.

## Code-first: автоматический deriving

Для DTO с codecs и схемой подключите оба независимых PPX:

```lisp
(library
 (name entity_http)
 (libraries base domain typed-endpoint typed-endpoint-mapper)
 (preprocess
  (pps ppx_deriving_yojson typed-endpoint-ppx typed-endpoint-mapper-ppx)))
```

Если поля совпадают, достаточно указать внешний тип:

```ocaml
module Entity_dto = struct
  type t = { id : int; name : string }
  [@@deriving yojson, jsonschema,
    mapper_from { source = [%type: Domain.Entity.t] }]
end
```

Генерируется `Entity_dto.of_domain : Domain.Entity.t -> Entity_dto.t`.
Поля DTO перечисляются один раз, в объявлении типа. Дополнительные исходные
поля Domain игнорируются; совместимость `id` и `name` проверяет компилятор.

Для отличающихся представлений задаются только исключения:

```ocaml
module Entity_dto = struct
  type t =
    { id : string [@mapper.from.convert Entity_id.to_string]
    ; name : string [@mapper.from.field "title"]
    ; status : Status_dto.t [@mapper.from.convert Status_dto.of_domain]
    ; display : string
        [@mapper.from.compute
          (fun (entity : Domain.Entity.t) -> String.uppercase entity.title)]
    }
  [@@deriving yojson, jsonschema,
    mapper_from { source = [%type: Domain.Entity.t] }]
end
```

Эквивалентный mapper:

```ocaml
let of_domain (source : Domain.Entity.t) : t =
  { id = Entity_id.to_string source.id
  ; name = source.title
  ; status = Status_dto.of_domain source.status
  ; display = String.uppercase source.title
  }
```

Входящие преобразования объявляются независимо:

```ocaml
module M = Typed_endpoint_mapper

module Create_entity_request = struct
  let project_id_of_string value =
    Result.map_error (Project_id.of_string value)
      ~f:(fun message -> M.Mapping_error.make ~code:"invalid_id" ~message)
  ;;

  type t =
    { project_id : string [@mapper.into.result project_id_of_string]
    ; name : string
    }
  [@@deriving yojson, jsonschema,
    mapper_into
      { target = [%type: Domain.Create_entity.t]
      ; fallible = true
      }]
end
```

Результат:

```ocaml
val to_domain :
  t -> (Domain.Create_entity.t, Typed_endpoint_mapper.Mapping_error.t) Result.t
```

Без `fallible = true` генерируется обычная функция `t -> Domain.Create_entity.t`.
В fallible режиме простые поля и total converters автоматически оборачиваются
в `Ok`; `result`-конвертер должен возвращать `Mapping_error.t` в ошибке.
Поля обрабатываются один раз, по порядку объявления; ошибка останавливает
последующие преобразования. Путь содержит целевое OCaml-имя поля.
`mapper_from` тоже поддерживает `fallible = true` и `[@mapper.from.result f]`.

| Аннотация | `mapper_from` | `mapper_into` |
| --- | --- | --- |
| Нет аннотаций | Копирование одноимённого поля Domain | Копирование поля DTO в одноимённое поле цели |
| `field "label"` | Другое имя исходного поля | Другое имя целевого поля |
| `convert f` | Total-функция от исходного поля | Total-функция от поля DTO |
| `result f` | Fallible-функция от исходного поля | Fallible-функция от поля DTO |
| `compute f` | Total-функция от всего источника | Не поддерживается |
| `skip` | Не требуется: проекция задаётся полями DTO | Не включать поле DTO в цель |

Полные имена аннотаций — `mapper.from.*` и `mapper.into.*`. На одном DTO можно
указать оба deriver и независимые настройки каждого направления. Например,
вычисленное response-поле отмечается `[@mapper.from.compute f] [@mapper.into.skip]`.
`compute` нельзя совмещать с `field`, `convert` или `result` того же направления;
`skip` нельзя совмещать с другими входящими настройками. Два поля не могут
маппиться в одно целевое поле. `result` без fallible режима отклоняется.

Для `type t` функции называются `of_domain` / `to_domain`; для `type entity` —
`entity_of_domain` / `entity_to_domain`. `.mli` может выводить те же сигнатуры
через deriving на полном объявлении записи. Конвертеры могут оставаться
приватными в `.ml`; их expressions в атрибутах `.mli` не выполняются.

MVP поддерживает непараметризованные публичные records. PPX не раскрывает
внешний Domain: `mapper_into` строит целевую запись из полей DTO с учётом
rename/skip. Если цели нужны дополнительные поля, компилятор потребует их;
для такого преобразования используйте внешний mapper либо обычную функцию
с явными дополнительными аргументами. Для abstract цели вызывайте публичный
constructor обычной функцией. Defaults и бизнес-правила не выводятся.
Вложенные records, option, list и array преобразуются явными функциями,
например `[@mapper.into.result (M.Converter.list Child.to_domain)]`.

## Contract-first: внешний total mapper

```lisp
(library
 (name entity_http)
 (libraries base domain dto typed-endpoint-mapper)
 (preprocess (pps typed-endpoint-mapper-ppx)))
```

```ocaml
open! Base

module Domain = struct
  type t = { name : string; revision : int; internal_note : string }
end

module Dto = struct
  type t = { name : string; version : int }
end

let to_dto =
  [%mapper
    fun (source : Domain.t) ->
      ({ name; version = source.revision } : Dto.t)]
;;
```

Эквивалентный OCaml:

```ocaml
let to_dto (source : Domain.t) : Dto.t =
  { name = source.name; version = source.revision }
;;
```

Непосредственное поле `name` копируется из источника. Форма `name = name`
имеет тот же смысл: ocamlformat может превратить её в pun. Чтобы обратиться к
одноимённой локальной переменной, используйте `name = (name : string)` либо
переименуйте локальную переменную. Другие выражения сохраняют обычный lexical
scope. Вложенные записи автоматически не переписываются.

Целевая запись всегда перечисляется целиком; record update не поддерживается.
Переименование, вычисляемые поля, ID, вложенные DTO и коллекции задаются обычными
выражениями и функциями. Например, `id = Entity_id.to_string source.id` или
`children = List.map source.children ~f:Child_mapping.to_dto`.

Пропуск исходных полей разрешён: это проекция. Новое обязательное поле цели,
удалённое используемое поле источника и несовместимые типы обнаружит компилятор.
Новое неиспользуемое исходное поле не ломает проекцию.

## Внешний result mapper

```ocaml
module M = Typed_endpoint_mapper

module Request = struct
  type t = { name : string; version : string }
end

let parse_version text =
  match Int.of_string_opt text with
  | Some version -> Ok version
  | None ->
    Error (M.Mapping_error.make ~code:"invalid_version" ~message:"expected integer")
;;

let from_request =
  [%mapper_result
    fun (source : Request.t) ->
      ({ name; version = parse_version source.version } : Dto.t)]
;;
```

В `mapper_result` сокращённое поле означает `Ok source.name`; каждое явно
заданное выражение должно возвращать `Result` с `Mapping_error.t`. Для total
вычисления используйте `Ok (...)`. Поля вычисляются один раз, слева направо;
первая ошибка прекращает обработку. В total mapper порядок вычисления полей
соответствует обычному OCaml record expression; используйте чистые expressions.

PPX добавляет имя целевого OCaml-поля в путь ошибки. `Converter.list` и
`Converter.array` добавляют индекс. Вложенный mapper получает путь вроде
`items[1].project_id`. Это путь mapping, а не JSON Pointer: wire-имена могут
отличаться. Путь доступен структурно через `Mapping_error.path`; `to_string`
предназначен для читаемой диагностики, а не машинного parsing.

`Converter.option` сохраняет `None`; решение о default или обязательности
остаётся в явном converter. Общий код ошибки и сообщение не содержат исходного
значения автоматически. Не включайте в публичные сообщения секреты.

Ошибка mapping не является `Decode_error`. Controller сам выбирает объявленный
HTTP response. Бизнес-валидация и транзакции остаются в domain/application.
Исключения пользовательских функций не перехватываются; ожидаемые ошибки
нужно возвращать через `Result`.

## Строгая эволюция источника

Если добавление любого исходного поля требует пересмотра mapping, используйте
закрытый record pattern:

```ocaml
let strict_to_dto =
  [%mapper
    fun ({ name = entity_name; revision; internal_note = _ } : Domain.t) ->
      ({ name = entity_name; version = revision } : Dto.t)]
;;
```

PPX локально включает warning 9 как ошибку. Новое поле источника потребует
обновить pattern; игнорируемые поля отмечаются явно. В этой форме сокращённое
копирование полей цели запрещено: нужны expressions с именами bindings,
отличными от целевых полей, либо аннотация выражения.

## Code-first и contract-first

Для code-first deriving живёт на рукописном DTO вместе с codecs и схемой.
Для contract-first внешний mapper не требует аннотаций на generated DTO.
Модуль mapping живёт рядом с controllers и обращается к экспортированным определениям
`Generated_api.Dto`:

```ocaml
let of_domain =
  [%mapper
    fun (source : Domain.t) ->
      ({ id; name; note = Generated_api.Support.Absent }
       : Generated_api.Dto.Pet.t)]
;;
```

Здесь `Domain.t` — тип из примера `examples/openapi`, содержащий `id` и `name`.
Generated DTO не редактируются. После изменения OpenAPI сначала регенерируется
DTO, затем компилятор проверяет mapper. `Absent`, `Present None` и
`Present (Some value)` обрабатываются явно: отсутствие и null не взаимозаменяемы.

PPX не читает OpenAPI или определения внешних модулей, не выводит schema и
codecs. Это локальное преобразование AST; типы проверяет OCaml. Для abstract
цели используйте её публичный constructor в обычной mapper-функции.

## ID, enum и границы автоматизации

- Для независимо развивающегося wire contract предпочитайте строковый ID
  и явный проверяющий domain constructor на входе; formatter ID — на выходе.
- Общий стабильный ID можно переиспользовать в DTO, если HTTP-слой предоставляет
  codec/schema и Domain не получает HTTP-зависимостей. Общую библиотеку ID
  стоит выделять при реальном переиспользовании.
- Enum можно переиспользовать при одинаковой семантике. Для другого множества
  внешних значений или независимой эволюции нужен отдельный wire enum и явный
  исчерпывающий `match`; включайте warning 8 как ошибку в mapping-модуле.
- Обычный Yojson variant кодируется массивом. Строковый enum требует codec,
  соответствующего wire contract; mapper не меняет JSON-представление.
- Обратное преобразование объявляется отдельно. Проекция не обязана иметь
  обратную функцию, а одинаковые имена constructors не доказывают семантику.

Не поддерживаются автоматическая интроспекция внешних типов, registry
конвертеров, вывод enum correspondence, накопление всех ошибок и генерация
inverse. Сложный mapper остаётся обычной функцией OCaml и использует те же
runtime helpers без PPX.

Тесты находятся в `mapper-ppx/test`: небольшие expect-сценарии, `.ml/.mli`,
compile-positive и compile-negative проверки эволюции типов, derived и generated
DTO, schema validation и in-memory HTTP. Оба способа используют один генератор
типизированного конструирования records и общие runtime helpers. Ядро,
HTTP adapters и OpenAPI codegen от mapper не зависят.
