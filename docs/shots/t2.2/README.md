# Снимки T2.2 (профиль, награда после обучения, 2x опыт)

**Статус: NOT VERIFIED.** 2026-11-10 ночью экран Mac был заблокирован: `tools/shot.sh` даёт «could not create image from window», TweenService в Play не идёт, эмуляция телефона не применяется (viewport 800×600). Проверено в Studio Play через MCP (состояние GUI, тексты, AbsolutePosition/Size, ход анимаций по времени) и `lune run tests/profile`:
- обучение туром → `[BT] T2.2 reward of SUL_GOAT: 4 balls, legendary SMILEY` → экран награды: стадии `cards` (карточки вылетают по одной, раз в ~0,95 с, переворачиваются в FIRE, ICE, LIGHTNING, PLANT) → `spin` → `spinning` (лента −1712 → −3263 → −3950 → −4163 → −4195, замедляется) → `stopped` (под указателем SMILEY, смещение 0,0 px, `SpinOn` = 16 — как решил сервер) → `boost` («2x XP · 15 MIN», LET'S PLAY!);
- `claim` → площадка: «LEVEL 1 · 0/150 XP», бейдж «2x XP 14:23», PLAY подсвечен (`PlayLit`), бейдж исчезает, когда буст кончился;
- `DebugXp = 160` → NEW BALL!: «LEVEL 2!», «NEW BALL!», карточка BOMB, «BOMB +1», «TAP TO CONTINUE»; 6 шаров;
- дуэль: `draft own = 0,1,3,2,16,23`, предложения только из своих, «YOUR BALLS: 6 / 27»; итог «+60 XP (2x)».

Не проверено глазами: как всё выглядит, вспышки и «+1» (твины), телефон 844×390 (раскладка посчитана: на холсте 1168×540 плашка уровня x 354–864, PLAY x ≥ 978, текст 20 → 14,4 px), повторный вход Stop/Play в Studio (DataStore выключен в Studio: «Enable Studio Access to API Services» не включён, профиль живёт в памяти и при Stop теряется; сохранение и перезаход проверены только в `tests/profile` на макете DataStore — NOT VERIFIED на настоящем DataStore).

## Снять утром (экран разблокирован, окно Studio видно)
1. Play. Без доступа к API профиль всегда новый. С доступом — до Play в Edit: `game.ServerScriptService:SetAttribute("DebugFreshProfile", true)` (атрибут переходит в Play; новый профиль не сохраняется), после съёмки снять.
2. Сервер (MCP `execute_luau`, Server): `local s = game.ServerScriptService s:SetAttribute("DebugTutorTour", true)`
3. Клиент (Client): `workspace:SetAttribute("BTRewardAuto", true)` — LET'S PLAY! нажмётся сам через 3 с.
4. Терминал: `tools/burst.sh docs/shots/t2.2/raw 75 1` и сразу
5. Клиент: `game.ReplicatedStorage.Remotes.Action:FireServer("tutor")` — если обучение первое, после победы придёт награда (≈ 13 с: карточки 4,4 с, рулетка ждёт 3 с и крутится 4,2 с, LEGENDARY 2,2 с, буст 3 с), затем площадка. Если награда уже была в этом Play — Stop/Play (без API профиль новый) и с шага 2.
6. После площадки (в том же Play): клиент `game.ReplicatedStorage.Remotes.Action:FireServer("queue", 1)`, `tools/shot.sh 09-draft-5 docs/shots/t2.2` на драфте; дождаться итога — `tools/shot.sh 10-result-xp docs/shots/t2.2`.
7. На площадке: сервер `game.ServerScriptService:SetAttribute("DebugXp", 400)`, сразу `tools/burst.sh docs/shots/t2.2/raw-level 4 0.5` — NEW BALL!.
8. Телефон: клиент `workspace:SetAttribute("BTEmulate", "844x390")`, Stop/Play и шаги 2–5 в `raw-phone` (награда и площадка).
9. Выбрать кадры: `01-card-flip` (карточка в повороте), `02-cards-4`, `03-spin-moving`, `04-spin-stop`, `05-legendary`, `06-boost`, `07-plaza-level-boost-play` (полоска, бейдж, подсвеченный PLAY), `08-new-ball`, `09-draft-5`, `10-result-xp`, `11-phone-reward`, `12-phone-plaza`; `raw*` удалить. Открыть и проверить глазами.

Повторный вход на настоящем DataStore: Game Settings → Security → Enable Studio Access to API Services (это настоящие данные места — решение пользователя), `DebugFreshProfile` снят, Play → обучение → награда → Stop → Play: сразу площадка, уровень, коллекция и бейдж те же. Первые минуты заново — `DebugFreshProfile = true` в Edit перед Play.
