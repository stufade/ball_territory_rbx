# Снимки T2.1 (обучение-мультик)

**Статус: NOT VERIFIED.** 2026-11-10 ночью экран Mac был заблокирован: `tools/shot.sh` и MCP `screen_capture` не снимают окно, viewport в Play 1×1. Обучение проверено lune-тестами (`tests/tutor`) и в Studio Play через MCP: тексты, видимость, положение кольца и руки у кнопки силы, усиление пульса, время. Не проверено глазами: как всё выглядит, рука на враге в сцене C (нужна проекция камеры), затемнения (твины стоят без отрисовки), телефон 844×390.

## Снять утром (экран разблокирован, окно Studio видно)
1. Play.
2. Сервер (MCP `execute_luau`, Server): `game.ServerScriptService:SetAttribute("DebugTutorTour", true)`
3. Терминал: `tools/burst.sh docs/shots/t2.1/raw 60` и сразу
4. Клиент (Client): `game.ReplicatedStorage.Remotes.Action:FireServer("tutor")` — обучение с начала; тур сам жмёт TAP, POWER, тап во врага и стоит по 3 с на: A-boom, A-wild, A-tap, B-power (до силы), B-grab (после), C-dir (подсказка), C-ko, D-final (середина финала). Затем победа (5 с) и площадка с PLAY.
5. Телефон: клиент `workspace:SetAttribute("BTEmulate", "844x390")`, повторить 3–4 в `raw-phone`.
6. Выбрать кадры: `01-A-boom`, `02-A-wildfire`, `03-A-tap`, `04-B-before`, `05-B-after`, `06-C-hint`, `07-C-ko`, `08-D-final`, `09-win`, `10-plaza-play`, `11-phone-B`, `12-phone-C`, `13-phone-plaza`; `raw*` удалить.

Ручной проход без тура: Play за нового игрока (флаг в атрибуте игрока, новый Play — новый игрок), кликать TAP, кнопку силы, врага. `DebugTutorSpeed = 0` замораживает обучение на нужном кадре, `1` — дальше.
