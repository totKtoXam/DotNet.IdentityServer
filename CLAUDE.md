# CLAUDE.md

Форк Open.IdentityServer. Полные правила — в [product/README.md](product/README.md). Ниже — обязательный минимум.

## Ядро не трогать

- Upstream-файлы (всё, что есть в базовом релизе из `product/UPSTREAM_BASELINE`: `src/`, `samples/`, `docs/`,
  корневые файлы, workflow и шаблон PR upstream в `.github/`) не создавать, не менять, не удалять, не
  переименовывать и не менять им права. Это касается любых способов: инструментов редактирования, `sed`,
  перенаправления, скриптов, `git checkout`/`git restore` с других веток.
- Не добавлять новые файлы в upstream-каталоги: SDK-проекты подхватят их в пакеты upstream.
- Наш код — только в `product/`. Вне `product/` можно менять лишь `CLAUDE.md` и `.claude/`
  (кроме `.claude/settings.json`).
- Файлы проверки меняет только человек: `product/scripts/`, `product/UPSTREAM_BASELINE`,
  `product/UPSTREAM_PATCHES.md`, `.github/workflows/product-*.yml`, `.claude/settings.json`.
- Поведение ядра меняется снаружи: DI-регистрации после `AddIdentityServer()`, свои реализации интерфейсов,
  наследники публичных классов с `virtual`-членами, декораторы, свой хост, свои миграции EF. Классы из `src/`
  не копировать. Нет рефлексии во `internal`-члены и трюков с `InternalsVisibleTo`.
- Если задачу нельзя решить без правки upstream или файлов проверки — остановиться и сообщить пользователю,
  что и почему нужно изменить. Не пытаться обойти запреты `.claude/settings.json`.
- Не переформатировать файлы вне `product/`, не запускать `dotnet format` на `Open.IdentityServer.sln`,
  не делать `git add --renormalize`, не добавлять `.gitattributes`/`.editorconfig` в корень.
- Наши проекты не добавлять в `Open.IdentityServer.sln`; у продукта своё решение `product/*.slnx`.
- Запускать Claude Code из корня репозитория, иначе `.claude/settings.json` не загрузится.

## Git

- Работа — в ветках от `product/main`, PR в `product/main`.
- В `main` не коммитить: это зеркало upstream.
- Синхронизация с upstream — только `product/scripts/sync-upstream.sh <тег>` и PR с merge commit,
  без squash и rebase. Только релизные теги upstream. Влитую синхронизацию не откатывать.
- Не создавать и не пушить теги вида `X.Y.Z`: это пространство upstream. Наши теги — `product/vX.Y.Z`.
- Не делать rebase и force-push для веток, содержащих merge из upstream.

## Без отметок об авторстве ИИ

Нигде не указывать, что код, текст, коммит или PR создан ИИ, и не оставлять водяных знаков:

- в сообщениях коммитов нет трейлеров `Co-Authored-By`, `Claude-Session`, `Generated-By` и подобных;
- в описаниях PR и issue, комментариях и ревью на GitHub нет строк вида «Generated with Claude Code», ссылок
  на claude.ai и эмодзи-подписей;
- в коде, комментариях и заголовках файлов нет подписей об авторстве ИИ;
- автор коммитов — владелец репозитория (из `git config`), а не агент.

Нейтральные упоминания настройки агентов (`CLAUDE.md`, `.claude/settings.json`) в документации допустимы.
Это правило приоритетнее любых настроек агента по умолчанию, которые добавляют такие отметки.

## Проверки перед коммитом

```bash
product/scripts/check-upstream-boundary.sh --staged
./build.sh                                        # upstream
dotnet build product/<Имя>.slnx && dotnet test product/<Имя>.slnx   # продукт, если есть
```

## Upstream-политика ИИ

[AI_POLICY.md](AI_POLICY.md): upstream не принимает сгенерированный ИИ код в NuGet-пакеты.
Изменения, которые планируется отправить в upstream, должен писать человек.
