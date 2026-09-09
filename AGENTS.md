# Инструкции для агентов

## Область проекта

- `lib/` — framework-agnostic ядро. Оно не должно зависеть от Opium, Cohttp или
  другого конкретного HTTP server.
- `opium/` — единственное место для зависимости от Opium.
- Текущий адаптер использует API Opium 0.18; смену major/minor версии оформляй
  как отдельную migration с проверкой публичного adapter API.
- `dream/` — адаптер для Dream 1.0.0~alpha8; Dream API не добавляй в ядро.
- `eio/` — нативный direct-style адаптер для cohttp-eio 6.3; собственный router
  остаётся внутренней деталью пакета `typed-endpoint-eio`.
- `testing/` — framework-free in-memory backend. Не добавляй сюда зависимости
  от конкретного web framework.
- `test/` — regression tests и небольшие OpenAPI snapshots.
- `examples/petstore/` — backend-independent пример приложения, разделённый на
  `domain/`, `application/`, `infrastructure/` и `http/`; отдельные entrypoint
  поддерживаемых HTTP-фреймворков находятся в `servers/`.
- В Petstore сохраняй направление зависимостей: controller → application
  service → repository port. Сервисы работают с `Domain`, контроллеры отвечают
  за DTO и HTTP-статусы, а конкретные репозитории выбираются только в
  composition root.
- Асинхронный repository adapter должен разделять с backend один тип эффекта;
  передавай его через `Base.Monad.S`. Не скрывай зависимости сервисов или
  контроллеров в глобальных mutable-реестрах.
- Repository ports в Petstore stateless и принимают transaction-scoped
  `~conn`. Application services тоже stateless: они получают `~database` и
  определяют границу `with_connection`/`transaction`. Controller может
  получать `Database.t` через group context, но не `Database.connection`.
- Метаданные пакетов задаются в `dune-project`; сгенерированные `.opam` вручную
  не редактируются.

## Общие принципы

- Используй `.ocamlformat` как единственный источник правил форматирования.
- Предпочитай простой читаемый код, небольшие связные модули и явные
  инварианты. Не добавляй абстракции без практической необходимости.
- По умолчанию используй immutable-данные.
- Во всех новых `.ml` и `.mli` используй `open! Base`. К функциям Stdlib
  обращайся явно через `Stdlib`.
- Основной тип модуля называй `t`, сигнатуру — `S`, функтор — `Make`.
- Для ожидаемых ошибок публичного API используй `Option.t` или `Result.t`;
  throwing-вариант при необходимости называй с суффиксом `_exn`.
- Публичный API и odoc-комментарии размещай в `.mli`. Комментарии должны
  объяснять ограничения и инварианты, а не пересказывать код.

## Инварианты typed-endpoint

- Декларация маршрута является общим источником данных для runtime и OpenAPI.
  При изменении request/response semantics проверяй обе стороны.
- Сохраняй type-level связь между path/query-параметрами и аргументами handler,
  а также между объявленными responses и вариантами результата.
- Group prefix состоит только из статических сегментов. Не обходи проверку
  typed path через router wildcard; backend-specific маршруты оформляй через
  `Unsafe.route` и не публикуй в OpenAPI.
- Не используй `Obj.magic`, unchecked casts или `Raw` для обхода типовой модели
  без явно документированной необходимости.
- Автоматические decode errors должны иметь предсказуемый статус и JSON shape;
  policy разрешается в порядке endpoint → group → compile, а изменения
  фиксируй regression test.
- Wire shape JSON-ответа задавай явным `Response_payload.S`. Не вводи
  глобальный wrapper; пагинацию и envelope оформляй как DTO соответствующего
  endpoint.
- Для DTO сначала используй общие аннотации `ppx_deriving_yojson`: `[@default]`,
  `[@key]` и `[@name]`. `ppx_deriving_jsonschema` понимает их и должен строить
  схему того же wire shape; не дублируй их через `[@jsonschema.option]` или
  `[@jsonschema.key]`.
- Ограничения, которые поддерживает `ppx_deriving_jsonschema`, задавай его
  аннотациями на типе или поле. `Json_schema` используй для параметров,
  заголовков, enum, collections, dictionaries и других схем без подходящего
  DTO-типа.
- Не редактируй сгенерированную PPX-схему как дерево `Yojson.Safe`. Для
  недостающего scalar wire shape введи небольшой manifest type с собственным
  `t_jsonschema`; `Json_schema.Unsafe` оставляй только для документированного
  JSON Schema keyword, которого ещё нет в безопасном DSL.
- Новый backend реализует `Typed_endpoint.Backend.S` в отдельном пакете и не
  добавляет framework-зависимость в ядро.
- `Backend.S.body_to_string` обязан соблюдать переданный лимит без
  предварительного неограниченного буферизования body.
- `Backend.S.respond_empty` не должен выставлять `Content-Type`, а
  `respond_string` обязан возвращать `text/plain; charset=utf-8`. Собственный
  роутер при 405 должен перечислять доступные методы в `Allow`.
- `Backend.S.combine` должен сохранять порядок переданных маршрутов: ядро
  заранее ставит статические пути перед пересекающимися path-capture.
- Общие middleware не добавляй в ядро: framework middleware остаётся снаружи,
  а типизированные зависимости и авторизацию выражай через `Context`/`Guard`.
- Ядро выражает эффекты через `Backend.S.io`. В Lwt-адаптерах реализуй
  `Backend.S.Io` как `Base.Monad.S` и используй его `Let_syntax`; Eio handler
  оставляй direct-style. Не используй `lwt_ppx`.
- Если тип вычисления предоставляет `Let_syntax`, используй `ppx_let`
  (`let%bind`, `let%map` и `and`) вместо вложенных вызовов `bind`/`map`.
- Не добавляй другие PPX, если задачу можно ясно решить обычным OCaml.

## Тесты и проверки

- Основные команды: `make build`, `make test`, `make fmt`.
- Для печатаемых OpenAPI/JSON результатов используй `ppx_expect`. Разделяй
  независимые сценарии; не создавай один новый огромный snapshot.
- Для нескольких независимых печатаемых значений ставь отдельный `[%expect]`
  сразу после каждого вывода. Не объединяй schemas или ошибки разных случаев в
  один общий блок ожиданий.
- Не продвигай snapshots и форматирование автоматически во время обычной
  проверки.
- Изменение публичного контракта сопровождай regression test или обновлением
  существующего snapshot с объяснением причины.

## Правила репозитория

- Markdown пиши на русском, текст в коде — на английском.
- Не добавляй CI без отдельного запроса.
- Не запускай `git commit` самостоятельно.
