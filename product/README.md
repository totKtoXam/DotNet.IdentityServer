# Правила работы с форком

Этот репозиторий — форк [RockSolidKnowledge/Open.IdentityServer](https://github.com/RockSolidKnowledge/Open.IdentityServer).
Цель правил — чтобы обновления из upstream вливались без конфликтов, а наш продукт при этом не ломался.

## Главный принцип

**Ядро (код upstream) не трогаем. Весь наш код живёт отдельно и расширяет ядро снаружи.**

Базовый релиз — релиз upstream, влитый в ветку. Он записан в [`UPSTREAM_BASELINE`](UPSTREAM_BASELINE)
(тег и коммит), файл обновляет только скрипт синхронизации. Upstream-файл — любой файл базового релиза.

Проверка [`check-upstream-boundary.sh`](scripts/check-upstream-boundary.sh) сравнивает всё дерево с базовым
релизом и требует:

0. коммит базового релиза есть в истории ветки, и после него не влит другой релиз upstream
   (так ловятся squash синхронизации, синхронизация вручную и откат синхронизации);
1. каждый upstream-файл на месте и побайтно совпадает с upstream (содержимое и права), кроме файлов из
   [реестра патчей](UPSTREAM_PATCHES.md);
2. каждый файл, которого нет в upstream, лежит в нашей зоне (таблица ниже);
3. `.claude/settings.json` запрещает ИИ-агентам правку всех upstream-путей и файлов самой проверки.

## Зоны владения

| Зона | Владелец | Кто меняет |
|------|----------|------------|
| `src/`, `samples/`, `docs/`, корневые файлы upstream (`README.md`, `build.sh`, `Directory.Build.props`, `global.json`, `NuGet.config`, `*.sln`, `.gitignore`, `LICENSE`, ...) | upstream | никто; исключение — патч из [реестра](UPSTREAM_PATCHES.md), вносит человек |
| `.github/workflows/{dotnet,docs,nuget-publish}.yml`, `.github/PULL_REQUEST_TEMPLATE.md` | upstream | никто |
| `product/scripts/`, `product/UPSTREAM_BASELINE`, `product/UPSTREAM_PATCHES.md`, `.github/workflows/product-*.yml`, `.claude/settings.json` | мы, файлы проверки | только человек |
| остальное в `product/`, `CLAUDE.md`, `.claude/` | мы | человек и ИИ-агенты |

Новые файлы вне `product/` создаём только там, где этого требует инструмент. Список таких мест задан в
`is_product_owned` в скрипте проверки; расширять его — отдельным PR.

Добавлять файлы внутрь upstream-каталогов тоже нельзя: SDK-проекты включают все `*.cs` из своей папки,
поэтому новый файл в `src/...` молча попадёт в пакет upstream.

## Как расширять, не меняя upstream

Open.IdentityServer рассчитан на расширение через DI. Проверено по исходникам `2.0.0` и `3.1.3`.

**Замена сервисов.** Свои реализации регистрируем **после** `AddIdentityServer()` — последняя регистрация
побеждает. До `AddIdentityServer()` работает только для сервисов, которые upstream регистрирует через `TryAdd*`;
`IEndpointRouter`, `IUserSession`, `IClientSecretValidator`, `IApiSecretValidator` и (в 3.x)
`IUserSessionEventsService` он регистрирует обычным `Add*`, и ранняя регистрация молча проиграет.
Готовые методы билдера: `AddProfileService<T>`, `AddResourceOwnerValidator<T>`, `AddClientStore<T>`,
`AddResourceStore<T>`, `AddPersistedGrantStore<T>`, `AddCorsPolicyService<T>`, `AddRedirectUriValidator<T>`,
`AddCustomAuthorizeRequestValidator<T>`, `AddCustomTokenRequestValidator<T>`, `AddExtensionGrantValidator<T>`,
`AddSecretParser<T>`, `AddSecretValidator<T>`, `AddUserSession<T>`, `AddAuthorizeInteractionResponseGenerator<T>`.
Регистрации `ISecretParser`, `ISecretValidator`, `IExtensionGrantValidator`, `Endpoint` не заменяют, а дополняют друг друга.

**Наследование.** Публичные классы с `virtual`-членами: `DefaultClaimsService`, `DefaultTokenService`,
`DefaultTokenCreationService`, `DefaultRefreshTokenService`, `DefaultProfileService`, `TokenResponseGenerator`,
`AuthorizeResponseGenerator`, `DiscoveryResponseGenerator`, `ProfileService<TUser>` из AspNetIdentity,
EF-хранилища `ClientStore`/`ResourceStore`/`PersistedGrantStore`. Наследуемся и регистрируем наследника.

**Только через обёртку интерфейса** (классы `internal`): валидаторы запросов (`TokenRequestValidator`,
`AuthorizeRequestValidator`, `TokenValidator` и др.), обработчики эндпоинтов, `DefaultIdentityServerInteractionService`,
`EndpointRouter`. Хелпер декораторов upstream тоже `internal` — пишем свой декоратор.

**Эндпоинты.** Новый путь — `AddEndpoint<T>(name, path)`. Встроенный маршрутизатор ищет точное совпадение пути,
первый найденный побеждает. Чтобы подменить встроенный эндпоинт, заменяем его регистрацию `Endpoint`.
Шаблоны путей — через свою реализацию публичного `IEndpointRouter`; проверку включённых эндпоинтов
(`EndpointsOptions`) в ней нужно повторить самим.

**Конвейер.** `UseIdentityServer()` собран из публичных частей (`BaseUrlMiddleware`, `ConfigureCors`,
аутентификация, `MutualTlsEndpointMiddleware`, `IdentityServerMiddleware`) плюс внутренняя проверка `Validate()`.
Если она мешает, конвейер собирается в хосте вручную; после каждой синхронизации сверяем его с `UseIdentityServer()`.

**UI.** В библиотеке UI нет, его даёт хост через `UserInteractionOptions` (`LoginUrl`, `ConsentUrl`, ...).
Стартовая точка — Quickstart UI из `samples/Quickstarts/6_AspNetIdentity`: копируем в `product/`, после этого
копия наша; в README папки пишем, из какого тега upstream она взята. В скопированном `.csproj` убираем
`Version="1.0.0-*"` у пакетов и задаём версию базового релиза в `product/Directory.Packages.props`.
Копировать примеры и шаблоны можно, копировать классы из `src/`, чтобы изменить их, — нельзя.

**EF Core.** Свои миграции — в своём проекте: `ConfigureDbContext = b => b.UseNpgsql(cs, o => o.MigrationsAssembly("<наш проект>"))`.
Свои таблицы — через наследника `ConfigurationDbContext<T>` / `PersistedGrantDbContext<T>` и
`AddConfigurationStore<T>()` / `AddOperationalStore<T>()`. В проекты и миграции upstream ничего не добавляем.
После синхронизации с upstream — `dotnet ef migrations add` в нашем проекте миграций.

**Ключи.** Автоматической ротации ключей в библиотеке нет: реализуем `ISigningCredentialStore` и `IValidationKeysStore`.

**Запрещено:** рефлексия во `internal`-члены; трюк с `InternalsVisibleTo` (назвать наш тестовый проект как
тестовый проект upstream и подписать `key.snk`).

**Что без патча не сделать:** изменить логику внутри `internal`-валидаторов запросов и обработчиков эндпоинтов.
Такие случаи — через [реестр патчей](UPSTREAM_PATCHES.md) и, по возможности, PR в upstream.

## Структура продуктового кода

- Проекты — `product/src/<Проект>`, тесты — `product/tests/<Проект>`, своё решение — `product/<Имя>.slnx`.
  Наши проекты в `Open.IdentityServer.sln` не добавляем. CI собирает и тестирует каждое `product/*.slnx`.
- `product/Directory.Build.props` и `product/Directory.Build.targets` отсекают корневые настройки upstream
  (`VersionPrefix`, `Company`, `WarningsAsErrors`). Наши общие MSBuild-настройки — только в них.
  Центральное управление версиями — `product/Directory.Packages.props`.
- Корневой `NuGet.config` содержит локальный источник `./nuget`, которого нет в свежем клоне (его создаёт
  `./build.sh`). Либо `mkdir -p nuget` перед первой сборкой, либо свой `product/NuGet.config` с `<clear/>` и nuget.org.
- Корневой `global.json` действует на любую команду `dotnet` в репозитории; менять его нельзя.
- Свои правила `.gitignore` — в `product/.gitignore`, корневой `.gitignore` принадлежит upstream.
- Ссылка на ядро (решается при создании хоста):
  - **рекомендуется** `PackageReference` на пакеты `Open.IdentityServer.*` с nuget.org той же версии, что базовый релиз;
    библиотеки upstream и сами ссылаются друг на друга пакетами;
  - `ProjectReference` на `src/...csproj` — только если понадобится патч кода пакета; ссылка соберёт из исходников
    только этот проект, соседние придут пакетами.

## Гигиена git и редактора

Стиль upstream неоднороден (сотни файлов без перевода строки в конце, с пробелами в конце строк, с BOM и без,
9 файлов с CRLF). Любое автоформатирование upstream-файла даёт diff на весь файл и конфликт при следующей синхронизации.

- Windows: клонировать с `git clone -c core.autocrlf=input <url>`. Git for Windows по умолчанию ставит `true`,
  и тогда `build.sh` в рабочей копии получает CRLF и не запускается. Для уже существующего клона:
  `git config core.autocrlf input`, затем на чистом дереве `git rm -rq --cached . && git reset --hard`.
- Редактор сохраняет окончания строк и кодировку (BOM) файла как есть.
- Никогда не запускать `git add --renormalize`.
- Format on save, Code Cleanup, сортировка `using` — только для `product/` (`product/.editorconfig` с `root = true`).
- `dotnet format` — только на нашем решении: `dotnet format product/<Имя>.slnx`.
- `.gitattributes` и `.editorconfig` в корень не добавляем — они изменят upstream-файлы.
- Локальная проверка перед каждым коммитом: `git config core.hooksPath product/scripts/hooks`.
  Тегам upstream локально быть не обязательно: базовый релиз записан в `UPSTREAM_BASELINE`.
  Нужна полная история: в shallow-клоне — `git fetch --unshallow origin`.

## Когда правка upstream неизбежна

1. Убедиться, что задачу нельзя решить расширением (см. выше).
2. Правку вносит человек, а не ИИ-агент.
3. Минимальный diff: не переформатировать, не переименовывать, не сортировать `using`, не менять окончания строк и кодировку.
4. Пометить место комментарием `FORK-PATCH: <причина>` — проверка требует его во всех форматах с комментариями.
5. Добавить файл в [UPSTREAM_PATCHES.md](UPSTREAM_PATCHES.md) в том же PR.
6. Если исправление полезно всем — PR в upstream. Учтите [AI_POLICY.md](../AI_POLICY.md):
   upstream принимает в пакеты только код, написанный человеком.

Нельзя даже через реестр: удалять или перемещать upstream-файлы, массово переименовывать namespace и сборки
`Open.IdentityServer`, менять `Directory.Build.props`, `global.json`, `NuGet.config`, `src/Directory.Build.targets`.

## Ветки

| Ветка | Назначение | Правило |
|-------|------------|---------|
| `main` | зеркало `upstream/main` | только fast-forward из upstream, своих коммитов нет |
| `product/main` | наш продукт, ветка по умолчанию | только через PR |
| `feature/<тема>`, `fix/<тема>` | наша работа | PR в `product/main`, merge через **Squash** |
| `sync/upstream-<тег>` | синхронизация с upstream | PR в `product/main`, merge через **Create a merge commit** |

Sync-PR нельзя сквошить и ребейзить: git потеряет связь с историей upstream. В эксперименте после squash
`3.0.0` следующая синхронизация с `3.1.3` дала конфликты в 40 файлах, после обычного merge — ни одного.
Если sync-PR всё же сквошнули, проверка упадёт («not in the history»). Исправление: открыть новый PR из той же,
не сквошенной ветки `sync/upstream-<тег>` в `product/main` и влить его через **Create a merge commit**.

Влитую синхронизацию не откатываем (`git revert -m 1` оставляет релиз в истории, а содержимое — старым, и
следующая синхронизация смешает версии; проверка это ловит). Если новый релиз сломал продукт — чиним продукт
следующим PR. Если откат уже влит — откатываем откат.

## Теги

- Теги upstream — простой semver (`2.0.0`, `3.1.3`). Их не создаём, не двигаем и не пушим в форк:
  push числового тега запускает release-workflow upstream. CI берёт теги прямо из upstream.
- Наши релизы — `product/v<версия>`, например `product/v0.1.0`. Простой semver занимать нельзя: по нему
  MinVer считает версию пакетов `Open.IdentityServer.*`, а проверка считает такой тег релизом upstream.

## Синхронизация с upstream

Синхронизируемся с **релизными тегами**, а не с произвольным состоянием `upstream/main` или веток `release/*`.

```bash
# Один раз в клоне
git remote add upstream https://github.com/RockSolidKnowledge/Open.IdentityServer.git

# 1. Обновить зеркало main (push сам отклонит не fast-forward)
git fetch upstream --tags
git push origin refs/remotes/upstream/main:refs/heads/main

# 2. Влить релиз в продукт (из актуальной product/main)
git switch product/main && git pull --ff-only
product/scripts/sync-upstream.sh 3.1.3   # ветка sync/upstream-3.1.3: merge, UPSTREAM_BASELINE, проверка
./build.sh
git push -u origin sync/upstream-3.1.3
# PR sync/upstream-3.1.3 -> product/main, merge через "Create a merge commit"
```

Вместо шага 1 можно `gh repo sync totKtoXam/DotNet.IdentityServer -b main`. Кнопку **Sync fork** на GitHub
нажимать только при выбранной ветке `main`: на главной странице открыта ветка по умолчанию `product/main`.

При конфликте:

- в файле из реестра патчей — берём версию upstream и заново применяем наш `FORK-PATCH`;
- если upstream сам исправил то, ради чего был патч, — берём версию upstream и удаляем строку из реестра;
- любой другой конфликт означает, что upstream-файл был изменён мимо правил, — разобраться, откуда правка.

В sync-PR: merge, разрешение конфликтов, новые правила `permissions.deny`, если их потребует проверка
(upstream добавил файл в корень), и минимальная адаптация нашего кода, без которой он не собирается.
Новую функциональность — отдельными PR.

## Проверки

Workflow [`product-ci.yml`](../.github/workflows/product-ci.yml) на каждый PR в `product/main`, каждый push в неё
и раз в сутки:

- `upstream-boundary` — берёт теги из upstream, отклоняет числовые теги, созданные в форке, проверяет скрипты
  и запускает [`check-upstream-boundary.sh`](scripts/check-upstream-boundary.sh);
- `product-build` — собирает и тестирует upstream (`./build.sh`) и каждое `product/*.slnx`.

Локально:

```bash
product/scripts/check-upstream-boundary.sh            # текущий коммит
product/scripts/check-upstream-boundary.sh --staged   # индекс (это же делает pre-commit hook)
```

## Защита от ИИ-агентов

`.claude/settings.json` запрещает Claude Code правку upstream-путей и файлов проверки (`permissions.deny`) и
отключает подписи агента в коммитах и PR (`attribution`). Он загружается, только если Claude Code запущен
**из корня репозитория**: при запуске из подкаталога запреты не действуют.

Запрет защищает от случайной правки инструментами редактирования и распознанными командами записи в Bash
(`sed`, `tee`, перенаправление), но не от произвольных процессов (`git checkout`, скрипты). Поэтому:

- граница — pre-commit hook и проверка `upstream-boundary` в CI;
- изменения файлов проверки (скрипты, реестр, `UPSTREAM_BASELINE`, workflow, `.claude/settings.json`) в PR
  человек проверяет отдельно: PR может ослабить проверку, которая его же и оценивает.

## Настройки GitHub

Сейчас ruleset `product/main` разрешает только Squash и не требует проверок — **до первого sync-PR** привести его
к настройкам ниже, иначе синхронизацию влить правильно нельзя.

- **Actions:** отключить `.NET`, `Docs` и `Publish NuGet Packages` (Actions → workflow → ⋯ → Disable workflow).
  `.NET` запускает сборку на каждый push в `main`, а push тега — попытку публикации в NuGet.
  После каждой синхронизации проверять, что они остались выключенными.
- **Ruleset `product/main`:** обязательные проверки `upstream-boundary` и `product-build` (это имена jobs;
  проверку можно выбрать, только если она запускалась за последние 7 дней). Методы слияния — Merge и Squash.
  **Require linear history** не включать: она запрещает merge-коммиты, без которых не работает синхронизация.
  GitHub не умеет задать метод для отдельных PR, поэтому sync-PR вливаем через Merge вручную.
- **Сообщение squash-коммита:** Settings → General → Pull Requests → Default commit message для squash —
  «Pull request title». Иначе маркер `[skip ci]` из коммитов PR отключит проверку на push.
- **Ruleset для тегов:** цель `[0-9]*`, Restrict creations, Restrict updates, Restrict deletions, Block force pushes,
  без bypass (при реальной необходимости ruleset временно выключается).
- **Dependabot:** version updates не включать. Если понадобятся — `.github/dependabot.yml` с
  `directories: ["/product/**"]` (файл нужно добавить в `is_product_owned`), иначе он будет править `src/`.
