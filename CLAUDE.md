# CLAUDE.md

Форк Open.IdentityServer. Полные правила — в [product/README.md](product/README.md). Ниже — обязательный минимум.

## Границы кода

- Файлы, которые есть в upstream-теге (`src/`, `samples/`, `docs/`, корневые файлы, workflow upstream), не менять.
  Проверить, upstream ли файл: `git cat-file -e "$(git describe --tags --abbrev=0 --match '[0-9]*.[0-9]*.[0-9]*'):<путь>"`.
- Новый код — только в `product/`. Вне `product/` можно создавать лишь `.github/workflows/product-*.yml` и этот файл.
- Расширять поведение через DI: свои реализации интерфейсов, декораторы, свой хост. Не копировать upstream-классы.
- Если правка upstream действительно неизбежна — сначала спросить пользователя. После согласия: минимальный diff,
  комментарий `FORK-PATCH: <причина>`, строка в `product/UPSTREAM_PATCHES.md` в том же коммите.
- Не переформатировать upstream-файлы, не менять окончания строк, не сортировать `using`, не переименовывать namespace.
- Не менять `Directory.Build.props`, `global.json`, `src/Directory.Build.targets`, `NuGet.config`, `key.snk`.

## Git

- Работа — в ветках от `product/main`, PR в `product/main`.
- В `main` не коммитить: это зеркало upstream.
- Синхронизация с upstream — только через `product/scripts/sync-upstream.sh <тег>` и merge commit, без squash и rebase.
- Не создавать теги вида `X.Y.Z`: это пространство upstream. Наши теги — `product/vX.Y.Z`.
- Не делать rebase и force-push для веток, содержащих merge из upstream.

## Проверки перед коммитом

```bash
product/scripts/check-upstream-boundary.sh origin/product/main
./build.sh
```

## Upstream-политика ИИ

[AI_POLICY.md](AI_POLICY.md): upstream не принимает сгенерированный ИИ код в NuGet-пакеты.
Изменения, которые планируется отправить в upstream, должен писать человек.
