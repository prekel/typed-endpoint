# Cohttp/Lwt без HTTP-фреймворка

`typed-endpoint-cohttp-lwt` компилирует декларации в собственную коллекцию
маршрутов и возвращает обычный Cohttp callback. Эффект backend — `Lwt.t`;
Opium, Dream и Eio не нужны. Пакет зависит от переносимого `cohttp-lwt`,
а конкретный транспорт выбирает приложение. Адаптер рассчитан на
`cohttp-lwt >= 6.3.0` и OCaml >= 4.14.1.

## Сервер

Для Unix entrypoint добавьте зависимости:

```lisp
(executable
 (name main)
 (libraries base cohttp-lwt-unix lwt.unix typed-endpoint typed-endpoint-cohttp-lwt))
```

Минимальный сервер с `GET /health`:

```ocaml
open! Base
open Typed_endpoint

module Backend = Typed_endpoint_cohttp_lwt
module Endpoint = Make (Backend)
open Endpoint

let health =
  get / "health"
  |> documented ~operation_id:"health"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Health" ()))
  ==> fun ok () () -> respond ok "ok"
;;

let compiled =
  compile_exn
    [ Group.make_with_context
        ~context:(Context.return ())
        ~description:"Health"
        [ health ]
    ]
;;

let () =
  let callback = Backend.callback (Compiled.app compiled) in
  let server = Cohttp_lwt_unix.Server.make ~callback () in
  Lwt_main.run (Cohttp_lwt_unix.Server.create ~mode:(`TCP (`Port 8080)) server)
;;
```

`Backend.callback routes` принимает connection, `Cohttp.Request.t` и
`Cohttp_lwt.Body.t`, возвращая `(Cohttp.Response.t * Cohttp_lwt.Body.t) Lwt.t`.
Connection не используется адаптером. Для встраивания без connection есть
`Backend.dispatch routes ~request ~body`.

Типизированный ответ остаётся buffered: backend создаёт Cohttp body из готовой
строки. Заголовки ответа сохраняются, в том числе повторные `Set-Cookie`.
Пустой ответ не получает `Content-Type`, текстовый использует
`text/plain; charset=utf-8`. Неизвестный путь возвращает 404; известный путь
с другим методом — 405 и список разрешённых методов в `Allow`.

## Middleware и body

Оборачивайте callback обычными функциями Cohttp/Lwt. Они могут изменять request
до dispatch и response после его завершения. Порт, TLS, timeouts и завершение
сервера остаются в приложении. Пример request ID middleware и route-aware
access log находится в [entrypoint Petstore](../examples/petstore/servers/cohttp_lwt_server.ml).
Для guards и request-scoped зависимостей доступны `Backend.Request.http`
и `Backend.Request.header`.

Адаптер читает body только при `Request_body.read`. Он накапливает chunks
до заданного лимита, возвращает ошибку при превышении и не читает последующие
chunks. Повторный `Request_body.read` использует сохранённый результат.
Middleware, прочитавшее body раньше, обязано передать замену.

Адаптер не дренирует оставшееся body. Стандартный сервер Cohttp/Lwt делает это
перед отправкой ответа и повторным использованием соединения, поэтому лимит
ограничивает буферизацию, но не объём данных, который сервер примет по сети.
Transport timeout и политика соединений задаются снаружи. Исключения
и отмена Lwt не перехватываются адаптером.

## Переход с Opium

Сначала перенесите маршруты в `typed-endpoint-opium` по
[руководству по миграции](opium_migration.md). Чтобы затем сменить backend,
объявляйте контроллеры и группы через `Make (B : Backend.S)`, используйте
`B.Io.Let_syntax`, а сервисы передавайте явно. Такой граф уже показан в Petstore.

После переноса замените `Typed_endpoint_opium` на
`Typed_endpoint_cohttp_lwt` в composition root, пересоберите декларации и
подключите `Backend.callback` вместо `Typed_endpoint_opium.mount`.
Сервисы и repository adapters остаются на Lwt. Opium middleware и обращения
к его native request/response нужно перенести на Cohttp API; готовая Opium
коллекция routes не является Cohttp/Lwt коллекцией.

Для запуска Petstore:

```sh
opam exec -- dune exec examples/petstore/servers/cohttp_lwt_server.exe
```
