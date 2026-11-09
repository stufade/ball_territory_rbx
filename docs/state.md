# Состояние

Обновлено: 2026-11-09.

**Репозиторий:** `~/Desktop/new-game/ball_territory_rbx`, GitHub `stufade/ball_territory_rbx`, ветка `main`.

**Текущий milestone:** M1.5 «Ощущение веба». M1 (логика, сервер, сеть) функционально принят, но вид отвергнут пользователем. Плейтест M1 отложен.

**Сейчас:** V1 (поле, шары, эффекты) принят. V2 — арена, HUD, все экраны как в Ball vs Ball и вебе — сделан, ждёт приёмки: снимки `docs/shots/v2/`, описание `docs/ui.md`, сцена `docs/scene.md`.

**Проверка вида:** `tools/shot.sh <имя>` снимает окно Studio и в Play (MCP screen_capture в Play не работает). Телефон: на клиенте `workspace:SetAttribute("BTEmulate", "844x390")`; короткие экраны держит `BTHold` (docs/ui.md). Каждый шаг сравнивается со скриншотами веба `ball_territory_web/out/v4/screens/` и референсами `../references/ui/Ball vs Ball/`.

**Режим:** автономно, пользователь проверит потом. Rojo и Studio не перезапускать.

**Открытые вопросы пользователю:**
- Точные цены — после симуляции экономики в M3.

**2026-11-09 21:40:** V1, V2, W3 приняты и запушены. W4 (лобби-площадка, зрители, party) прерван лимитом Claude до 01:50 МСК; продолжить: `orca orchestration send --to dispatch:ctx_1ee1dd6cfa95 --subject Продолжай --body ...`. Спека: scratchpad w4.md (копия задачи в Orca).
