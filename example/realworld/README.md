# Пример приложения

Это небольшой API статей, устроенный как обычное приложение, а не как набор
изолированных route-примеров. Он показывает пагинацию, JSON request/response,
валидацию, parse errors, DI, bearer-token guard и генерацию OpenAPI.

```text
domain             доменные типы без HTTP и JSON
article_store      конкурентное in-memory хранилище immutable-состояния
article_service    внедряемый application port и бизнес-валидация
dto                wire-типы и их JSON Schema
routes             общий функтор маршрутов
test               memory backend и end-to-end тест без web framework
servers            entrypoint для Opium, Dream и Eio
```

`Routes.Make` принимает только `Typed_endpoint.Backend.S` и функцию чтения
заголовка. Сервис внедряется через `Dependency.value`, а guard извлекает из
запроса пользователя. Поэтому бизнес-правила и декларации endpoint не нужно
переписывать при смене HTTP runtime.

## Тест

```sh
opam exec -- dune runtest --root . example/realworld/test
```

Memory backend выполняет скомпилированный route table напрямую. Тест проверяет
list/create/get/delete, отказ guard, validation и parse errors, 404/405, а также
объявленные в OpenAPI ответы `201`, `400` и `401`.

## Запуск

Каждая команда запускает API на `0.0.0.0:8080` (Opium использует свои
стандартные настройки интерфейса):

```sh
opam exec -- dune exec --root . example/realworld/servers/opium_server.exe
opam exec -- dune exec --root . example/realworld/servers/dream_server.exe
opam exec -- dune exec --root . example/realworld/servers/eio_server.exe
```

Проверить API можно так:

```sh
curl http://localhost:8080/api/articles?page=1

curl \
  -H 'authorization: Bearer demo-token' \
  -H 'content-type: application/json' \
  -d '{"title":"Hello","body":"Portable endpoint"}' \
  http://localhost:8080/api/articles
```

Хранилище намеренно остаётся локальным. Для production вместо
`Article_service.seeded` можно собрать тот же record-порт поверх базы данных,
не меняя DTO и контракт маршрутов.
