# Dependency injection

Ядро `typed-endpoint` не вводит контейнер или service locator. Зависимости
передаются handler явно через типизированный `Context.t`, поэтому endpoint
остаётся независимым от web-framework и пригодным для runtime и OpenAPI
одновременно.

Неизменяемое окружение создаётся один раз при запуске и превращается в context
через `Dependency.value`:

```ocaml
type env =
  { posts : Posts_service.t
  ; clock : Clock.t
  }

let context = Dependency.value env

let get_post =
  make_with ~context (* declaration omitted *)
  @@ fun user_id post_id env () ->
  Posts_service.get env.posts ~user_id ~post_id
;;
```

Request-scoped зависимость задаётся через `Dependency.of_request`. Несколько
источников объединяются слева направо через `Context.both`, а итоговую форму
можно привести к предметной записи через `Context.map`:

```ocaml
let context =
  Context.both
    (Dependency.value env)
    (Dependency.of_request Request_id.from_request)
  |> Context.map ~f:(fun (env, request_id) -> { env; request_id })
```

Такой подход имеет несколько полезных свойств:

- зависимости видны в точке декларации endpoint;
- unit-тест может передать маленькую fake-реализацию;
- endpoint остаётся чистой декларацией HTTP-контракта;
- Opium и другие backends не получают зависимости ядра.

Обычный `make` сохраняет прежнее поведение и передаёт handler исходный
`B.req`. Если нужны одновременно request и зависимости, используйте
`Context.both Context.request (Dependency.value env)`.

Если число сервисов становится большим, запись `env` следует разбивать на
предметные записи. Глобальное mutable state и динамический поиск сервисов не
используются.
