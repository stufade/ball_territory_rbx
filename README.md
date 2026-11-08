# Ball Territory — Roblox

Roblox-версия Ball Territory: шары-стихии красят поле и дерутся за землю. Рабочее название.

- Бриф: `docs/game-brief.md`
- Анализ идеи и журнал решений: `docs/idea-analysis.md`
- План: `docs/milestones.md`, текущее состояние: `docs/state.md`
- Передача контекста с веба: `docs/roblox-handoff.md`
- Источник правды по правилам: веб-прототип [stufade/ball_territory_web](https://github.com/stufade/ball_territory_web), файл `public/game.js`
- Референсы UI и витрины лежат вне репозитория: `../references/`

## Команды

Инструменты ставит [Rokit](https://github.com/rojo-rbx/rokit) по `rokit.toml`: `rokit install`.

```bash
rojo build -o build/ball_territory.rbxl   # сборка места
rojo serve                                 # синхронизация со Studio
stylua --check src tests                   # формат
selene src tests                           # линт
luau-lsp analyze --platform roblox --definitions=tools/roblox-types.d.luau src tests   # типы
lune run tests/hello                       # чистые правила в lune
```

Rojo и Studio («Element vs Element», placeId 96446158283661):

1. Один раз `rojo plugin install`, затем перезапустить Studio (плагин ставится в `~/Documents/Roblox/Plugins`).
2. В корне проекта `rojo serve` (порт 34872), держать запущенным.
3. В Studio: Plugins → Rojo → Connect, адрес `localhost:34872`. Появятся `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`.
4. Синхронизируются только скрипты из `src/`. Сцена (Workspace) живёт в самом месте и сохраняется из Studio.
