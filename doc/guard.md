# Guard и авторизация

`Guard.v` выполняет framework-agnostic проверку запроса и возвращает typed
context либо контролируемый HTTP-ответ. Успешный context передаётся handler
через `make_with`:

```ocaml
let authenticated =
  Guard.v
    ~status:`Unauthorized
    ~response:(Response.json (module Error_response))
    ~check:(fun request ->
      Auth.authenticate request
      |> Lwt.map (Result.map_error ~f:Error_response.unauthorized))

let get_profile =
  make_with ~context:authenticated (* declaration omitted *)
  @@ fun user () -> Profile.get user
```

Guard запускается до path/query/body decoding и до handler. При отказе handler
и декодеры не вызываются. Объявленный response автоматически добавляется в
OpenAPI; если его статус совпадает с бизнес-ответом или parse error, JSON Schema
дедуплицируются либо объединяются через `oneOf`.

Guard, DI и исходный request компонуются через `Context.both`. Context
разрешаются слева направо; первый отказ останавливает цепочку:

```ocaml
let context =
  Context.both
    authenticated
    (Context.both (Dependency.value env) Context.request)
```

Один guard можно переиспользовать в нескольких endpoint. Context не хранится в
глобальном mutable state, тип handler не расширяется через unchecked casts, а
ядро не получает зависимость от Opium.
