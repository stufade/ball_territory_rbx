# Правила на Luau: API для сервера

`ReplicatedStorage.Shared.Rules` (`src/shared/Rules`), `--!strict`, без Roblox API, работает и в lune. Перенос `ball_territory_web/public/game.js`. Каждый матч — свой объект `State`, сервер ведёт сколько угодно матчей.

**Матч**
- `Rules.newMatch(seats, opts) -> State`: `seats = {{e = id, ctl = "userId" | nil}}`, `ctl = nil` — бот. `opts.layout`: `"ffa"` (24×20, по умолчанию), `"duel"` (арена 16×14), `"web"` и `"webDuel"` (20×24 веба). Ещё `opts.round`, `opts.pace` (для дуэли `Config.DUEL_PACE`), `opts.seed`.
- `Rules.step(S)` — один шаг 1/30 с. Конец: `S.done`, победитель `Rules.leader(S)`, земля `S.counts[e]`.
- `Rules.timeScale(S)` — множитель часов сервера: 1/3 после первой реакции вида, 0,5 пока человек видит CHOOSE DIRECTION. Пока `S.slow > 0`, сервер уменьшает его на `DT` каждый шаг (как `room.js`).

**Ввод** (любые числа, NaN и чужие `e` отбрасываются с `false`)
- `Rules.aim(S, e, dx, dy)` — прицел до старта; `Rules.launch(S)` — старт, после него `aim` не действует.
- `Rules.redirect(S, e, dx, dy)` — смена направления: в окне CHOOSE DIRECTION (`S.t <= S.promptUntil`) или в финале не чаще раза в 0,2 с.
- `Rules.press(S, e)` — кнопка силы, `true` если заряд был полный. `ball.auto = true` — автосила, `ball.prompts = false` — без подсказок.

**Вывод**
- `Rules.drain(S)` — события `{id, kind, d}`: `power`, `rx` (`d.k` — имя реакции), `hit`, `ko`, `steal`, `spawn`, `prompt`, `final`, `ready` и эффекты сил.
- `Rules.snapshot(S, meta)` — снимок как в вебе: `o` (владелец клетки, `.` или `a`+id), `g` (верхний слой, индекс в `Config.TOP`), `f` (угасание), `b` (шары: e, x, y, ang, hp, alive, charge, флаги, ...), `c` клоны, `k` бомбы, `u` пузыри, `ev` — события с прошлого снимка (снимок их забирает).

**Дуэль** (`Rules.Duel`): `newDraft(first)`, `draftTurn`, `draftPick(d, side, e)` по порядку 1-2-2-1; `new(teams, ctls)`, `need`, `choose`, `newRound(duel) -> State`, `endRound(duel) -> победитель или -1`. Боты: `botDraft`, `botChoose`, `pickFree(used, rand)`.

**Числа** — `Rules.Config`: `P`, `PACE`, `DUEL_PACE`, `STRONG/WEAK`, `DSTRONG/DWEAK`, `TOUCH`, `CONV`, `CDS`, `REACTIONS` (42), раскладки поля `LAYOUTS`. `WEB_PACE` и `WEB_DUEL_PACE` — числа веба для теста паритета.

**Решения переноса**
- Клетки 1-based (`k = y*W + x + 1`), id стихий 0-based, как в вебе. ГСЧ — mulberry32 из `seedRandom`, бит в бит; таймеры слоёв округляются до float32, как `Float32Array`.
- Поворот: x и y меняются местами (отступы старта 5×4, пятна карты в четверти 24×20). Правила те же.
- `zoneStep` (угасание отрезанной земли) не перенесён: в вебе он не вызывается, правило убрано.
- Без зерна ГСЧ — `math.random`. У ботов драфта свой ГСЧ вместо `Math.random`.

**Баланс поля 24×20** (детерминирован, зёрна в тестах): `PACE` — `tests/tune` 8 попыток на 2 000 матчей, взят набор попытки 7. `DUEL_PACE` — `tune duel` (пары, 3 попытки), затем `tune duels` и точечные шаги по полным дуэлям с драфтом и контрами ботов. Потолок темпа поднят с 3 до 4 (Ветер 3,73). `DSTRONG/DWEAK` — 60 раундов на каждую пару, `STRONG/WEAK` — из `tests/balance`.

**Тесты** (`lune run tests/<имя>`): `parity` — сравнение с вебом на 20×24; `trace` + `node tests/web/trace.mjs` — пошаговая сверка; `balance`, `duel`, `tune` — баланс на новом поле.
