# Что можно позаимствовать у типизированных FP-фреймворков

## Положение typed-endpoint

По архитектуре `typed-endpoint` ближе всего к Scala Tapir: HTTP endpoint
описывается неизменяемым значением, а затем интерпретируется как runtime route
и OpenAPI. От Haskell Servant проект берёт сильную связь между аргументами
handler и HTTP-контрактом, а от http4s — параметризацию эффектом и внешнюю
композицию transport middleware.

Для OCaml это удачный компромисс. Полностью type-level DSL в стиле Servant
даст более сложные ошибки типов и потребует большого количества type-level
инфраструктуры, которой в языке нет. Полностью schema-first подход в стиле
Smithy4s, напротив, сделает генератор кода центром проекта. Текущий value-level
DSL проще расширять и отлаживать.

## Обзор подходов

### Haskell Servant

Servant реифицирует API в типе и использует одну декларацию для сервера,
клиента и документации. Полезны три более конкретные идеи:

- `NamedRoutes` представляет большой API вложенными records вместо
  позиционной цепочки обработчиков;
- `hoistServer` переводит все handlers из одного эффекта в другой естественным
  преобразованием;
- `MultiVerb` связывает обычный sum type результата с несколькими HTTP-ответами.

Переносить весь API в типы не стоит. Полезнее позаимствовать именованные
группы, преобразование эффекта и более компактное представление ответов.

Источники:

- [принципы Servant](https://docs.servant.dev/en/latest/principles.html);
- [NamedRoutes](https://docs.servant.dev/en/inserting_doc_namedroutes/cookbook/namedRoutes/NamedRoutes.html);
- [hoistServer](https://docs.servant.dev/en/stable/tutorial/Server.html);
- [MultiVerb](https://docs.servant.dev/en/latest/cookbook/multiverb/MultiVerb.html).

### Scala Tapir

Tapir разделяет неизменяемое описание `Endpoint` и присоединяемую к нему
server logic. В типе endpoint отдельно представлены security input, обычный
input, ожидаемая ошибка и успешный output. Mapping входов и выходов
двунаправленный, поскольку та же декларация может интерпретироваться как
сервер или клиент.

Это наиболее полезное направление для `typed-endpoint`:

- отделить контракт endpoint от handler;
- собирать path/query/body в один record входа;
- иметь typed error и success output;
- в будущем интерпретировать декларацию как typed client;
- различать request middleware и endpoint-aware interceptors.

Источники:

- [описание endpoint и двунаправленные mappings](https://tapir.softwaremill.com/en/latest/endpoint/basics.html);
- [типизированные security inputs](https://tapir.softwaremill.com/en/latest/endpoint/security.html);
- [request и endpoint interceptors](https://tapir.softwaremill.com/en/v1.12.4/server/interceptors.html);
- [тестирование endpoint без сети](https://tapir.softwaremill.com/en/latest/testing.html).

### Scala Smithy4s

Smithy4s генерирует сервисную алгебру и набор endpoint из Smithy-модели, после
чего разные интерпретаторы строят серверы и клиенты. Middleware может видеть
метаданные конкретного сервиса и endpoint. Отдельный compliance suite проверяет
реализацию HTTP-протокола.

Schema-first code generation не должен становиться обязательным режимом
`typed-endpoint`, но стоит перенять:

- единый conformance suite для всех backend;
- endpoint-aware observability по `operation_id` и route template;
- чёткое разделение пользовательской service implementation и интерпретатора;
- contract tests, не использующие один и тот же encoder одновременно на стороне
  клиента и сервера.

Источники:

- [сервисы и endpoint в Smithy4s](https://disneystreaming.github.io/smithy4s/docs/design/services/);
- [endpoint-aware middleware](https://disneystreaming.github.io/smithy4s/docs/guides/endpoint-middleware/);
- [protocol compliance tests](https://disneystreaming.github.io/smithy4s/docs/protocols/compliance-tests/);
- [рекомендации по тестированию](https://disneystreaming.github.io/smithy4s/docs/guides/testing/).

### Scala http4s и ZIO HTTP

В http4s middleware является преобразованием HTTP-приложения. Библиотека
отдельно предоставляет request ID, timing, error handling, limits, metrics и
`ContextMiddleware`. Это подтверждает полезность текущей границы проекта:
логирование, CORS, compression и timeout должны оставаться в HTTP-адаптере, а
типизированная авторизация и зависимости endpoint — в `Context` и `Guard`.

ZIO кодирует зависимости, ожидаемую ошибку и результат как `ZIO[R, E, A]`, а
`ZLayer[RIn, E, ROut]` описывает построение одного набора сервисов из другого.
Это хороший ориентир для статического графа зависимостей, но встроенный
type-map или runtime service locator в OCaml для этого не нужен.

Источники:

- [http4s server middleware](https://http4s.org/v1/docs/server-middleware.html);
- [ZIO HTTP Endpoint API](https://ziohttp.com/concepts/endpoint/);
- [ZIO environment](https://zio.dev/reference/contextual/);
- [ZLayer](https://zio.dev/reference/contextual/zlayer/).

## Functor-only DI

### От чего именно можно отказаться

Можно полностью отказаться от:

- контейнера, который ищет зависимости по имени или типу во время запроса;
- глобального mutable registry;
- runtime reflection и автоматического выбора реализации сервиса;
- неявного получения repository внутри controller.

Нельзя отказаться от runtime-значений вообще. Пул соединений Caqti,
конфигурация, clock, logger и состояние in-memory repository появляются во
время запуска процесса. Функтор выбирает реализацию и связывает типы, но не
заменяет экземпляр ресурса.

Поэтому практичная модель выглядит так:

```text
compile time
  Database module + repository modules
                  │
                  ▼
       stateless service modules
                  │
                  ▼
      stateless controller modules
                  │
                  ▼
             Routes.Make

runtime
  config → database pool/state → App.compile → compiled app
```

Это static DI с одним явным runtime resource, а не runtime DI container.

### Production composition root с Caqti

Database port отвечает за выдачу connection и транзакционную границу:

```ocaml
module type Database = sig
  type 'a io
  type t
  type connection

  val with_connection :
    t ->
    on_error:(Persistence_error.t -> 'error) ->
    f:(conn:connection -> ('a, 'error) result io) ->
    ('a, 'error) result io

  val transaction :
    t ->
    on_error:(Persistence_error.t -> 'error) ->
    f:(conn:connection -> ('a, 'error) result io) ->
    ('a, 'error) result io
end
```

Repository port не хранит pool и принимает scoped connection явно:

```ocaml
module type Pet_repository = sig
  type 'a io = 'a Lwt.t
  type connection

  val find :
    conn:connection ->
    Pet_id.t ->
    (Pet.t option, Persistence_error.t) result io

  val save :
    conn:connection -> Pet.t -> (unit, Persistence_error.t) result io
end
```

Production `Database_caqti` хранит pool в `t`, а concrete connection скрывает
в `connection`. Repository adapters содержат только запросы и преобразование
строк. Поэтому один service use case может вызвать несколько repositories с
одним `~conn` и атомарно завершить общую транзакцию.

`Routes.Make` один раз собирает статический граф конкретного executable:

```ocaml
module Application =
  Petstore_app.Routes.Make (Backend) (Database_caqti) (Caqti_pet_repository)
    (Caqti_order_repository)
    (Caqti_user_repository)
```

Во время запуска создаётся только database pool. Сервисы и контроллеры
являются stateless-модулями внутри уже проверенного функтора:

```ocaml
let run database_uri =
  Db_pool.with_pool database_uri @@ fun pool ->
  let compiled =
    Application.compile ~auth ~database:pool
  in
  Server.run (Application.Endpoint.Compiled.app compiled)
;;
```

`Db_pool.with_pool` здесь означает lifecycle boundary: ресурс приобретается до
сборки приложения и гарантированно освобождается после остановки сервера.
Конкретная сигнатура будет зависеть от выбранного Caqti runtime. В Caqti есть
отдельные пакеты для Lwt и Eio, а драйвер может выбираться по URI или быть явно
прилинкован к executable:
[официальный репозиторий Caqti](https://github.com/paurkedal/ocaml-caqti).

### In-memory executable

Для ручного запуска используется тот же application graph, но другие
repository modules:

```ocaml
module Database = Database_memory.Make (Identity)

module Application =
  Routes.Make (Testing_backend) (Database) (Database.Pet_repository)
    (Database.Order_repository) (Database.User_repository)

let compiled =
  Application.compile ~auth ~database:(Database.create ())
```

HTTP-контракт, controller и service logic при этом не меняются.

### Unit tests

Для unit test удобно инстанцировать service functor с маленькими `Database` и
repository modules. Зависимости видны в параметрах функтора, а сценарий — в
явном `database` value:

```ocaml
module Stub_repository = struct
  type 'a io = 'a
  type connection = Fixtures.connection

  let find ~conn:_ _ = Ok (Some Fixtures.pet)
  let save ~conn:_ _ = Ok ()
end

module Pets = Pet_service.Make (Identity) (Test_database) (Stub_repository)

let result = Pets.find ~database:Fixtures.database Fixtures.pet_id
```

Функтор гарантирует соответствие порту на этапе компиляции. Для разных ответов
можно создать разные stub modules или хранить fixture state в изолированном
`Test_database.t`; глобальный mock registry не требуется.

### Почему не стоит помещать экземпляры в модули

Можно сделать функтор, принимающий модуль с `val database : t`, и убрать
`~database` из `App.compile`. Но это лишь прячет runtime value внутри модуля и
создаёт проблемы:

- нельзя поднять два независимых приложения в одном процессе;
- сложнее изолировать тесты;
- инициализация и освобождение pool становятся неявными;
- конфигурация начинает читаться в module initialization;
- зависимости хуже видны в месте запуска.

Функторы должны выбирать реализации и фиксировать граф типов. Значения должны
явно передавать состояние и ресурсы.

### Ограничения functor-only wiring

- Один собранный executable имеет один статический набор реализаций. Для
  переключения PostgreSQL/in-memory в том же бинарнике понадобится first-class
  module или обычное значение-интерфейс.
- Большие цепочки функторов ухудшают сообщения об ошибках и время компиляции.
- Циклические зависимости сервисов требуют изменения границ, а не усложнения
  DI-механизма.
- Эффекты всё равно должны совпадать: Lwt repository нельзя напрямую передать
  Eio controller без явного преобразования или отдельного adapter.

Для production обычно полезно собирать отдельные composition root modules или
executables: `petclinic-opium-caqti`, `petclinic-dream-caqti` и
`petclinic-eio-caqti`. In-memory composition root остаётся отдельным простым
вариантом для demo и ручного тестирования.

## Рекомендуемая граница DI

Следует придерживаться следующего разделения:

| Механизм | Назначение |
|---|---|
| Функтор | Выбор implementation module и проверка совместимости эффектов |
| Обычный value | Конкретный database pool или in-memory state |
| Composition root | Создание ресурсов и сборка полного графа |
| `Context` | Request-scoped данные и явная доставка готовых зависимостей handler |
| `Guard` | Типизированная аутентификация и авторизация |
| HTTP middleware | Logging, request ID, CORS, compression, timeout и tracing |

Текущий Petstore следует этой модели напрямую. `Routes.Make` принимает
`Database.S` и три stateless repository modules, а затем статически получает
из них service и controller modules. `App.compile` принимает один
`~database`; отдельных `Pet_service.t`, `Order_service.t`, `User_service.t`,
service locator или глобального registry нет. Application service выбирает
`with_connection` для чтения и `transaction` для записи. В
`Order_service.place` оба repository получают один transaction-scoped `~conn`.

## Приоритет практик для проекта

Согласованные следующие шаги, а также явно отклонённые варианты записаны в
[roadmap](roadmap.md). В частности, обязательный input record и `map_input` не
планируются: текущие curried handler arguments остаются основным API.

## Что переносить не следует

- Полностью type-level API Servant.
- Monadic `Context`: динамическая структура вычисления не позволит заранее
  вывести OpenAPI responses и security requirements.
- Глобальный контейнер зависимостей или type-map в стиле runtime DI.
- Обязательный schema-first code generation.
- Универсальные transport middleware в framework-agnostic ядре.
- Глобальные module-level экземпляры database pool или другого runtime-ресурса.

Итоговая цель — не «убрать runtime-зависимости», а сделать runtime-граф
полностью явным и статически проверяемым: функторы связывают реализации, а
короткий composition root создаёт и передаёт принадлежащие процессу ресурсы.
