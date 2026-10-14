# Постепенная миграция с Opium

`typed-endpoint-opium` можно подключить к существующему Opium-приложению без
замены сервера. Старые и типизированные маршруты временно работают вместе;
переносите их по одному, оставляя настройку порта, TLS, запуск сервера и общие
middleware в composition root приложения.

Руководство рассчитано на Opium 0.17.1–0.18, который поддерживает текущий
адаптер. Для нового major/minor релиза Opium сначала проверьте отдельную
совместимость адаптера.

## 1. Подключите адаптер рядом с существующими зависимостями

Добавьте `typed-endpoint` и `typed-endpoint-opium` в зависимости executable или
библиотеки, где объявляются новые маршруты. Если используете JSON DTO, добавьте
`typed-endpoint-ppx` и существующие PPX в stanza Dune:

```lisp
(executable
 (name main)
 (libraries base cohttp opium yojson typed-endpoint typed-endpoint-opium)
 (preprocess
  (pps ppx_let ppx_deriving_yojson typed-endpoint-ppx)))
```

Начните с отдельного endpoint-модуля, который использует Opium backend:

```ocaml
open! Base
open Typed_endpoint

module Endpoint = Make (Typed_endpoint_opium)
module Io = Endpoint.Io

open Io.Let_syntax
open Endpoint
```

`Endpoint.Io.t` здесь совпадает с `Lwt.t`, поэтому асинхронные handlers
используют `let%bind`/`let%map`, как и остальной Opium-код.

## 2. Перенесите один endpoint

Сначала выберите небольшой маршрут и перенесите его контракт: method и path,
входные параметры, формат тела, ответы и статусы. Ниже один и тот же
`GET /pets/:petId` до и после переноса. В обоих случаях он возвращает статус 200,
текст `Pet: <petId>` и `Content-Type: text/plain; charset=utf-8`.

До переноса Opium передаёт handler сырой request. Handler извлекает параметр
по имени и самостоятельно создаёт HTTP-ответ:

```ocaml
let legacy_get_pet request =
  let pet_id = Opium.Std.param request "petId" in
  Opium.Std.respond'
    ~code:`OK
    ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
    (`String ("Pet: " ^ pet_id))
;;

let legacy_app =
  Opium.App.empty |> Opium.App.get "/pets/:petId" legacy_get_pet
;;
```

После переноса path parameter и ответ объявляются в DSL. Handler получает
готовое значение `pet_id` и capability для ответа 200. Prefix группы добавляет
`/pets` к пути endpoint:

```ocaml
let get_pet =
  get /: arg "petId" (Parameter.string ~description:"Pet ID" ())
  |> documented ~operation_id:"getPet" ~summary:"Find a pet"
  |> accepts Request.empty
  |> returns (case `OK (Response.text ~description:"Pet label" ()))
  ==> fun pet_id ok () () -> respond ok ("Pet: " ^ pet_id)
;;

let pets_group =
  Group.make_with_context
    ~prefix:[ "pets" ]
    ~tags:[ "pets" ]
    ~description:"Pets"
    ~context:(Context.return ())
    [ get_pet ]
;;

let compiled = compile_exn [ pets_group ]
let typed_routes = Compiled.app compiled
```

В OpenAPI этот маршрут будет записан как `GET /pets/{petId}`. Код примера
оставляет `petId` строкой, чтобы сохранить прежний контракт. Если заменить codec
на `Parameter.int` и адаптировать handler, он получит `int`, а невалидное число
будет отклонено до его вызова. Такое изменение входного контракта и ответа при ошибке нужно
проверить отдельно.

При подключении typed-версии уберите старую регистрацию того же method/path.
Если в приложении есть другие legacy routes, оставьте их:

```ocaml
let app = Opium.App.empty |> Typed_endpoint_opium.mount typed_routes
;;
```

Для реальных DTO объявите wire shape через `ppx_deriving_yojson` и
`typed-endpoint-ppx`. Path, query и header parameters задайте в декларации
маршрута; JSON или другой request body читайте через `Request_body.read`.
Объявите все возможные response status и payload в `returns`: handler сможет
ответить только переданной ему capability. Подробности DSL приведены в
[быстром старте](quickstart.md).

## 3. Подключите typed routes к текущему приложению

Передайте уже скомпилированные routes в `Typed_endpoint_opium.mount`. Функция
принимает сначала коллекцию typed routes, затем существующее `Opium.App.t` и
возвращает новое приложение. Подставьте сюда текущий builder приложения и
ваше middleware; пример показывает место вызова `mount`:

```ocaml
let () =
  existing_opium_app
  |> Typed_endpoint_opium.mount typed_routes
  |> Opium.App.middleware request_id
  |> Opium.App.port 8080
  |> Opium.App.run_command
;;
```

Оставьте в этом же composition root прежние Opium middleware, настройки
transport и вызов запуска сервера. Сохраняйте их текущий порядок: он может
влиять на request logging, обработку ошибок и чтение request body. `mount` сам
не запускает сервер, не меняет port/TLS и не управляет ресурсами приложения.

Один вызов `mount` регистрирует все маршруты коллекции и один общий middleware
для ответа 405 с заголовком `Allow`. Во время поэтапного переноса допустимо
монтировать несколько независимых коллекций, но лучше объединить migrated
routes в один `compile` и выполнить один `mount`. Это оставляет одну общую
проверку методов независимо от количества маршрутов.

Проверьте, что старые и новые регистрации не пересекаются по method/path.
Внутренний порядок typed routes сохраняется компилятором, но при совпадениях с
legacy routes приоритет определяется также маршрутизатором Opium. Не полагайтесь
на порядок для намеренно дублирующихся маршрутов: удалите старую регистрацию и
проверьте результат через HTTP-тест.

## 4. Переносите по одному endpoint из нескольких групп

Рассмотрим приложение с тремя логическими группами: Pets, Users и Orders.
В каждой есть два endpoint. Сначала все шесть реализованы на Opium. Перенесём
только получение одного pet и одного user; списки pets/users и оба endpoint
Orders продолжат работать через прежние handlers.

| Группа | Endpoint | До переноса | После переноса |
| --- | --- | --- | --- |
| Pets | `GET /pets` | Opium | Opium |
| Pets | `GET /pets/:petId` | Opium | typed-endpoint |
| Users | `GET /users` | Opium | Opium |
| Users | `GET /users/:username` | Opium | typed-endpoint |
| Orders | `GET /orders` | Opium | Opium |
| Orders | `GET /orders/:orderId` | Opium | Opium |

### До переноса: три модуля с двумя Opium routes

В legacy-коде группы представлены модулями, каждый из которых регистрирует два
маршрута. Ответы здесь текстовые, чтобы пример показывал сборку приложения.
Используется общий `Endpoint` из начала руководства.

```ocaml
let legacy_text body =
  Opium.Std.respond'
    ~code:`OK
    ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
    (`String body)
;;

module Legacy_pets = struct
  let list_pets _request = legacy_text "Pets"

  let get_pet request =
    legacy_text ("Pet: " ^ Opium.Std.param request "petId")
  ;;

  let routes app =
    app
    |> Opium.App.get "/pets" list_pets
    |> Opium.App.get "/pets/:petId" get_pet
  ;;
end

module Legacy_users = struct
  let list_users _request = legacy_text "Users"

  let get_user request =
    legacy_text ("User: " ^ Opium.Std.param request "username")
  ;;

  let routes app =
    app
    |> Opium.App.get "/users" list_users
    |> Opium.App.get "/users/:username" get_user
  ;;
end

module Legacy_orders = struct
  let list_orders _request = legacy_text "Orders"

  let get_order request =
    legacy_text ("Order: " ^ Opium.Std.param request "orderId")
  ;;

  let routes app =
    app
    |> Opium.App.get "/orders" list_orders
    |> Opium.App.get "/orders/:orderId" get_order
  ;;
end

let app_before =
  Opium.App.empty
  |> Legacy_pets.routes
  |> Legacy_users.routes
  |> Legacy_orders.routes
;;
```

### Перенос: по одному typed endpoint в Pets и Users

Создадим по одной typed-группе для перенесённых endpoints. Каждый новый модуль
содержит одну декларацию и возвращает группу с соответствующим prefix и tag.
Для Orders typed-группа пока не нужна, поскольку её endpoints ещё не перенесены.

```ocaml
module Migrated_pets = struct
  let get_pet =
    get /: arg "petId" (Parameter.string ~description:"Pet ID" ())
    |> documented ~operation_id:"getPet" ~summary:"Find a pet"
    |> accepts Request.empty
    |> returns (case `OK (Response.text ~description:"Pet label" ()))
    ==> fun pet_id ok () () -> respond ok ("Pet: " ^ pet_id)
  ;;

  let group =
    Group.make_with_context
      ~prefix:[ "pets" ]
      ~tags:[ "pets" ]
      ~description:"Pets"
      ~context:(Context.return ())
      [ get_pet ]
  ;;
end

module Migrated_users = struct
  let get_user =
    get /: arg "username" (Parameter.string ~description:"Username" ())
    |> documented ~operation_id:"getUser" ~summary:"Find a user"
    |> accepts Request.empty
    |> returns (case `OK (Response.text ~description:"User label" ()))
    ==> fun username ok () () -> respond ok ("User: " ^ username)
  ;;

  let group =
    Group.make_with_context
      ~prefix:[ "users" ]
      ~tags:[ "users" ]
      ~description:"Users"
      ~context:(Context.return ())
      [ get_user ]
  ;;
end
```

Оба модуля используют общий `Endpoint`; не создавайте независимый backend или
сервер для каждой группы. У групп могут быть собственные contexts, guards и
политики decode errors. После создания `Group.t` их можно собрать в общий список,
даже если типы contexts различаются.

### После переноса: четыре legacy routes и два typed routes

В composition root явно оставим четыре legacy-регистрации. Для Pets и Users
регистрируем только списки: прежние `get_pet` и `get_user` уже заменены typed
декларациями. Orders подключаем прежним `Legacy_orders.routes` целиком.

```ocaml
let remaining_legacy_routes app =
  app
  |> Opium.App.get "/pets" Legacy_pets.list_pets
  |> Opium.App.get "/users" Legacy_users.list_users
  |> Legacy_orders.routes
;;

let compiled =
  compile_exn [ Migrated_pets.group; Migrated_users.group ]
;;

let openapi =
  Compiled.openapi
    ~config:(Openapi.Config.v ~title:"Application API" ~version:"1.0" ())
    compiled
;;

let app_after =
  Opium.App.empty
  |> remaining_legacy_routes
  |> Typed_endpoint_opium.mount (Compiled.app compiled)
  |> Opium.App.get "/openapi.json" (fun _request ->
    Typed_endpoint_opium.respond_json openapi)
;;
```

Все шесть endpoint продолжают работать в одном Opium-приложении с прежними
ответами. Служебный `GET /openapi.json` дополнительно публикует общий документ
для двух перенесённых endpoint. Не вызывайте здесь `Legacy_pets.routes` или
`Legacy_users.routes`: эти builders зарегистрируют также старые GET по ID/имени
и продублируют typed-маршруты.

### Что попадёт в общий OpenAPI

`Compiled.openapi compiled` вернёт один документ с двумя paths. Каждая операция
содержит описание, path parameter и responses из typed declaration:

| Метод | OpenAPI path | operationId | Tag |
| --- | --- | --- | --- |
| GET | `/pets/{petId}` | `getPet` | `pets` |
| GET | `/users/{username}` | `getUser` | `users` |

`GET /pets`, `GET /users` и оба Orders endpoint пока отсутствуют в документе,
хотя доступны в приложении.

Обе typed-группы компилируются вместе, поэтому `operation_id` должны быть
уникальными во всём документе; `compile` проверяет также конфликты typed routes
между группами. Чтобы следующим шагом перенести `GET /pets`, добавьте его typed
декларацию в список `Migrated_pets.group` и удалите соответствующую строку из
`remaining_legacy_routes`. Для первого перенесённого Orders endpoint создайте
typed-группу с prefix `orders`, добавьте её в тот же `compile` и оставьте в
legacy-регистрации только второй Orders endpoint. Общий OpenAPI расширится из
того же результата компиляции.

Несколько отдельных `mount` не собирают общий OpenAPI: `mount` работает только
с runtime routes. Объединяйте исходные группы до `compile`, затем получайте
`Compiled.app` и `Compiled.openapi` из одного результата.

Полный документ со всеми legacy Opium-маршрутами автоматически не появится:
у них нет typed declarations, из которых можно получить параметры и ответы.
`Unsafe.route` также исключён из OpenAPI. Если legacy API уже имеет отдельную
спецификацию и на переходном этапе нужен один документ для обеих частей, их
объединение нужно организовать отдельно; готового API импорта или объединения
OpenAPI-документов библиотека не предоставляет.

## 5. Переносите зависимости и middleware по границам

Общие HTTP concerns оставьте в Opium middleware: request ID, CORS, compression,
transport timeout и общий error boundary. Для логирования, которое должно знать
выбранный typed endpoint, используйте `compile ~interceptors`; interceptor
получает `Route_info` с шаблоном пути. Для типизированной авторизации и
request-scoped данных постепенно переходите на `Guard` и `Context`, прикрепляя
их к endpoint или группе.

Переносите бизнес-проверки вместе с объявленными ответами. Например, ожидаемую
ошибку валидации выражайте response constructor с соответствующим status и DTO,
а не исключением, которое прежний middleware преобразовывал в произвольный
ответ. Неожиданные исключения по-прежнему доходят до внешней границы обработки
ошибок приложения.

Тело запроса читается адаптером только при `Request_body.read`, с заданным
лимитом. Если Opium middleware уже потребляет stream тела, перенесите чтение в
одно место или обеспечьте замену stream: повторное потребление одного Opium body
может оставить typed handler без исходного содержимого.

## 6. Проверяйте каждый перенесённый маршрут

Для каждого endpoint сравните старую и новую реализацию по method/path,
status, заголовкам, content type, wire shape тела и поведению при ошибках.
Особенно проверьте percent-decoding параметров, повторные scalar query values,
невалидный JSON и превышение body limit. Если API публикует OpenAPI, помните,
что документ строится только из typed declarations: ещё не перенесённые legacy
routes в нём не появятся.

Бизнес-семантику удобно проверять через `typed-endpoint-testing`, а преобразование
запросов/ответов и интеграцию с Opium — отдельным adapter test. После завершения
переноса удалите legacy-регистрации и их временные обработчики; сервер, общие
middleware и Opium lifecycle остаются в приложении.
