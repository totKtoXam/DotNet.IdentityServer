# Правила работы с форком

Этот репозиторий — форк [RockSolidKnowledge/Open.IdentityServer](https://github.com/RockSolidKnowledge/Open.IdentityServer).
Цель правил — чтобы обновления из upstream вливались без конфликтов, а наш продукт при этом не ломался.

## Главный принцип

**Код upstream не трогаем. Весь наш код живёт отдельно.**

Upstream-файлом считается любой файл, который есть в последнем влитом upstream-теге
(`git ls-tree -r --name-only <тег>`). Сейчас это `2.0.0`.

| Зона | Владелец | Можно менять |
|------|----------|--------------|
| `src/`, `samples/`, `docs/`, корневые файлы upstream (`README.md`, `build.sh`, `Directory.Build.props`, `global.json`, `*.sln`, `LICENSE`, ...) | upstream | нет, только через [реестр патчей](UPSTREAM_PATCHES.md) |
| `.github/workflows/*` из upstream (`dotnet.yml`, `docs.yml`, `nuget-publish.yml`), `.github/PULL_REQUEST_TEMPLATE.md` | upstream | нет |
| `product/` | мы | да |
| `.github/workflows/product-*.yml` | мы | да |
| `CLAUDE.md` | мы | да |

Новые файлы вне `product/` создаём только там, где этого требует инструмент
(`.github/workflows/product-*.yml`, `CLAUDE.md`). Всё остальное — внутри `product/`.

## Как расширять, не меняя upstream

Open.IdentityServer спроектирован под расширение через DI. Вместо правки исходников:

- регистрируем свои реализации интерфейсов (`IProfileService`, `IResourceOwnerPasswordValidator`,
  `IClientStore`, `IResourceStore`, `IPersistedGrantStore`, `IExtensionGrantValidator`, `ICustomTokenRequestValidator`, ...);
- декорируем существующие сервисы (оборачиваем стандартную реализацию своей);
- добавляем свои endpoints, контроллеры и middleware в нашем хост-приложении;
- схему БД расширяем своими таблицами и своим `DbContext`, а не правкой миграций upstream.

Ссылки на upstream-проекты из `product/` — через `ProjectReference` на `src/...csproj`.

## Когда правка upstream неизбежна

1. Убедиться, что задачу нельзя решить расширением (см. выше).
2. Сделать минимальную правку: не переформатировать, не переименовывать, не сортировать `using`,
   не менять окончания строк и кодировку.
3. Пометить место комментарием `FORK-PATCH: <причина>`.
4. Добавить файл в [UPSTREAM_PATCHES.md](UPSTREAM_PATCHES.md) в том же PR.
5. Если исправление полезно всем — отправить PR в upstream. Учтите [AI_POLICY.md](../AI_POLICY.md):
   upstream принимает в пакеты только код, написанный человеком.

Нельзя: массово переименовывать namespace/сборки `Open.IdentityServer`, менять
`Directory.Build.props`, `global.json`, `src/Directory.Build.targets`, удалять или перемещать файлы upstream.

## Ветки

| Ветка | Назначение | Правило |
|-------|------------|---------|
| `main` | зеркало `upstream/main` | только fast-forward из upstream, своих коммитов нет |
| `product/main` | наш продукт, ветка по умолчанию | только через PR |
| `feature/<тема>`, `fix/<тема>` | наша работа | PR в `product/main`, merge через **Squash** |
| `sync/upstream-<тег>` | синхронизация с upstream | PR в `product/main`, merge через **Create a merge commit** |

Sync-PR нельзя сквошить: git потеряет связь с историей upstream, и следующая синхронизация
даст конфликты во всех файлах.

## Теги

- Теги upstream — простой semver (`2.0.0`, `2.1.0-rc1`). Их не создаём и не двигаем.
- Наши релизы тегируем как `product/v<версия>`, например `product/v0.1.0`.
  Простой semver занимать нельзя: по нему MinVer считает версию пакетов, а CI upstream публикует NuGet.

## Синхронизация с upstream

Раз в какое-то время (или при выходе нового релиза upstream):

```bash
# 1. Обновить зеркало main
git fetch upstream --tags
git switch main
git merge --ff-only upstream/main
git push origin main
git push origin --tags

# 2. Влить нужный релиз в продукт
product/scripts/sync-upstream.sh 2.1.0
./build.sh
git push -u origin sync/upstream-2.1.0
# PR sync/upstream-2.1.0 -> product/main, merge через "Create a merge commit"
```

Синхронизируемся с **релизными тегами**, а не с произвольным состоянием `upstream/main`.

При конфликте:

- в файле из реестра патчей — берём версию upstream и заново применяем наш `FORK-PATCH`;
- если upstream сам исправил то, ради чего был патч — берём версию upstream и удаляем строку из реестра;
- любой другой конфликт означает, что upstream-файл был изменён мимо правил — разобраться, откуда правка.

В sync-PR не добавляем новую функциональность: только merge и разрешение конфликтов.

## Проверка в CI

Workflow [`product-ci.yml`](../.github/workflows/product-ci.yml) на каждый PR в `product/main`:

- `upstream-boundary` — запускает [`check-upstream-boundary.sh`](scripts/check-upstream-boundary.sh)
  и падает, если изменён upstream-файл, которого нет в реестре. Для веток `sync/upstream-*` пропускается.
- `build` — собирает и тестирует решение скриптом upstream `./build.sh`.

Локально перед PR:

```bash
product/scripts/check-upstream-boundary.sh origin/product/main
```

## Настройки GitHub

- В `Settings → Rules` добавьте `Product CI / upstream-boundary` и `Product CI / build`
  в `Require status checks to pass` для `product/main`.
- Отключите workflow `Publish NuGet Packages` в `Actions` (кнопка `Disable workflow`) —
  это не требует правки файла upstream.
