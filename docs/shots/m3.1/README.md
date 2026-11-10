# Снимки M3.1 (валюты, вход 7 дней, задания, книга реакций)

**Статус: NOT VERIFIED в Studio.** 2026-11-10 ночью Studio был запущен без открытого места: MCP `get_studio_state` → «Place is not open», окна места нет (`tools/shot.sh` → «Studio window not found»). Открывать место и перезапускать Studio задача не разрешает, поэтому ни Play, ни снимков, ни проверки GUI через `execute_luau` нет.

Проверено вне Studio:
- `lune run tests/economy` — миграция v1 → v2, потолок опыта и плата уровней 10+, монеты за матч (режимы, лимиты, AFK, друг 20 в сутки, x2, серия 3/5/10), вход по UTC-дням (23:59:59 / 00:00, пропуск не сбрасывает, VOID на 7-й, цикл 2), задания (по тиру, сброс в 00:00 UTC, «все три» один раз), книга без дублей (каждые 10 → кристаллы, все 42 → 1000), сумма потоков = кошелёк.
- `lune run tests/profile` — весь сервер на макете Roblox: монеты дуэли в `result` и профиле, `LogEconomyEvent`, `Action daily` раз в сутки, `LoginDay`, AFK-матч на четверых без монет и опыта.
- `lune run tests/ui` — клиентские модули M3.1 на макете GUI (`tests/Gui.luau`), холсты 1168×540 (телефон 844×390) и 960×540: счётчики докручиваются (0 → 50, в середине 0 < n < 50), «+50» всплывает и исчезает, окно входа само открывается раз (не до первого матча, не поверх NEW BALL!), CLAIM шлёт `daily` один раз, TAKEN! и галочка, панель заданий (строки, «NEW IN 4h 59m»), книга (42 ячейки, 4 цветных, 38 «???», NEW!), тосты ждут площадки, всё прячется в матче, прямоугольники в пределах экрана и не задевают PLAY/PARTY/HOW TO PLAY, стик и прыжок.

Не проверено: как это выглядит (цвета, шрифты, обводки, эмодзи 🎁📜📖 на телефоне), твины `Theme.pop`, настоящий `AnalyticsService`, `IsFriendsWithAsync` с настоящим другом, DataStore (миграция v1 → v2 на живых записях).

## Снять утром (место открыто, экран разблокирован)
Одной командой после Play (Studio: Play, затем в терминале):

```bash
tools/burst.sh docs/shots/m3.1/raw 40 1
```

и сразу по шагам через MCP `execute_luau`:
1. Server: `game.ServerScriptService:SetAttribute("DebugFreshProfile", true)` до Play (в Edit), чтобы начать с обучения; иначе профиль из памяти. Пройти обучение или `DebugTutorTour = true` → награда → LET'S PLAY.
2. Client: `game.ReplicatedStorage.Remotes.Action:FireServer("queue", 1)` — дуэль; после итога (`02-result-coins`: «+N монета») площадка, окно входа откроется само (`03-daily-open`), нажать CLAIM! мышью — `04-daily-claimed` (TAKEN!, вспышка, счётчики докручиваются).
3. Server: `game.ServerScriptService:SetAttribute("DebugDay", 6)` → снова площадка: окно входа дня 7 с VOID (`05-daily-void`), CLAIM — лучи и конфетти (`06-void-claimed`). `DebugDay` потом снять (`nil`).
4. Клик 📜 — `07-quests`; клик 📖 — `08-book` (цветные найденные, «???»).
5. Телефон: Client `workspace:SetAttribute("BTEmulate", "844x390")` — `09-phone-plaza` (счётчики над PLAY, кнопки над прыжком, стик свободен), `10-phone-daily`, `11-phone-book`.
6. Выбрать кадры с этими именами, `raw` удалить, проверить глазами.

Проверка через состояние GUI, если экран снова заблокирован: Client `local c = game.Players.LocalPlayer.PlayerGui.BallUI.Band.Canvas; local w = c.Wallet; print(w.Visible, w:FindFirstChild("Value", true).Text)`, `c.WalletPop.Visible`, `AbsolutePosition`/`AbsoluteSize` у `Coins`, `DailyBtn`, `DailyPanel`, `BookPanel`. Докрутка идёт на Heartbeat и работает без твинов.
