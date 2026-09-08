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
  repository module
       │
       ▼
  service functor
       │
       ▼
  controller functor
       │
       ▼
  routes functor

runtime
  config → database pool → repository value → service value → compiled app
```

Это static DI с явными runtime instances, а не runtime DI container.

### Production composition root с Caqti

Repository port сохраняет абстрактные `io` и `t`:

```ocaml
module type Pet_repository = sig
  type 'a io
  type t

  val find : t -> Pet_id.t -> (Pet.t option, Persistence_error.t) Result.t io
  val save : t -> Pet.t -> (unit, Persistence_error.t) Result.t io
end
```

Production adapter хранит пул в своём `t`. Конкретный тип Caqti остаётся
внутри infrastructure-модуля:

```ocaml
module Caqti_pet_repository :
  Pet_repository with type 'a io = 'a Lwt.t =
struct
  type 'a io = 'a Lwt.t
  type t = Db_pool.t

  let find pool id = Db_pool.use pool (fun connection -> ...)
  let save pool pet = Db_pool.use pool (fun connection -> ...)
end
```

`Routes.Make` один раз собирает статический граф конкретного executable:

```ocaml
module Application =
  Petstore_app.Routes.Make (Backend) (Caqti_pet_repository)
    (Caqti_order_repository)
    (Caqti_user_repository)
```

Во время запуска создаются только ресурсы репозиториев. Сервисы и контроллеры
строятся внутри уже проверенного функтора:

```ocaml
let run database_uri =
  Db_pool.with_pool database_uri @@ fun pool ->
  let compiled =
    Application.compile
      ~auth
      ~pet_repository:pool
      ~order_repository:pool
      ~user_repository:pool
  in
  Server.run (Application.Endpoint.Dsl.Compiled.app compiled)
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
module Pet_repository = Pet_repository_memory.Make (Identity)
module Order_repository = Order_repository_memory.Make (Identity)
module User_repository = User_repository_memory.Make (Identity)

module Application =
  Routes.Make (Testing_backend) (Pet_repository) (Order_repository)
    (User_repository)

let compiled =
  Application.compile
    ~auth
    ~pet_repository:(Pet_repository.create ())
    ~order_repository:(Order_repository.create ())
    ~user_repository:(User_repository.create ())
```

HTTP-контракт, controller и service logic при этом не меняются.

### Unit tests

Для unit test удобно инстанцировать service functor с маленьким repository
module. Сам экземпляр `t` может быть record функций или заранее подготовленных
ответов:

```ocaml
module Stub_repository = struct
  type 'a io = 'a

  type t =
    { find : Pet_id.t -> (Pet.t option, Persistence_error.t) Result.t
    }

  let find t id = t.find id
  let save _ _ = Ok ()
end

module Pets = Pet_service.Make (Identity) (Stub_repository)

let repository =
  { Stub_repository.find = (fun _ -> Ok (Some Fixtures.pet)) }
in
let service = Pets.create ~repository in
...
```

Функтор гарантирует соответствие порту на этапе компиляции, а значение record
позволяет каждому тесту задавать собственный сценарий без глобального mock
registry.

### Почему не стоит помещать экземпляры в модули

Можно сделать функтор, принимающий модуль с `val repository : t`, и полностью
убрать аргументы `create`. Но это лишь прячет runtime value внутри модуля и
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
| Обычный record/value | Конкретный pool, repository, service или controller instance |
| Composition root | Создание ресурсов и сборка полного графа |
| `Context` | Request-scoped данные и явная доставка готовых зависимостей handler |
| `Guard` | Типизированная аутентификация и авторизация |
| HTTP middleware | Logging, request ID, CORS, compression, timeout и tracing |

Текущий Petstore следует этой модели напрямую. `Routes.Make` принимает три
repository modules и статически получает из них service и controller modules.
`App.compile` принимает три именованных repository values; отдельного
`Services.t`, service locator или глобального registry нет. Для in-memory
варианта это три независимых state values, а production adapter может передать
один общий pool через три repository interfaces.

## Приоритет практик для проекта

1. Вынести повторяющиеся проверки backend в единый conformance suite.
2. Передавать адаптерам `operation_id` и route template для логов и метрик.
3. Добавить mapping path/query/body в именованный input record.
4. Разделить чистое описание `Endpoint.t` и связанный с handler
   `Server_endpoint.t`.
5. Сделать codecs двунаправленными и добавить typed client interpreter.
6. Добавить явную lifecycle abstraction для database pool и других ресурсов в
   composition root, но не в HTTP-ядро.
7. Рассмотреть удобный sum-type API ответов поверх текущего строгого response
   builder.
8. При практической необходимости добавить `hoist` между application effect и
   backend effect.

## Что переносить не следует

- Полностью type-level API Servant.
- Monadic `Context`: динамическая структура вычисления не позволит заранее
  вывести OpenAPI responses и security requirements.
- Глобальный контейнер зависимостей или type-map в стиле runtime DI.
- Обязательный schema-first code generation.
- Универсальные transport middleware в framework-agnostic ядре.
- Глобальные module-level экземпляры database pool, repository или service.

Итоговая цель — не «убрать runtime-зависимости», а сделать runtime-граф
полностью явным и статически проверяемым: функторы связывают реализации, а
короткий composition root создаёт и передаёт принадлежащие процессу ресурсы.
