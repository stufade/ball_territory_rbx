# Ревью коммитов Cursor 42a0a56..d800d8c (2026-11-16)

Роль: luau-coder, Opus. Studio не трогал. Проверено по чек-листу `roblox-code-review`: обработчики remote (покупка, рулетка, косметика, вехи, дуэль), ProcessReceipt, профиль и миграции, утечки, PolicyService, лимит звука удара. Плюс добавка координатора: продукты с настоящими id (580ecf5), геймпассы, бейдж пака.

Проверки: `stylua src` чисто; `luau-lsp analyze` (свежая sourcemap) чисто во всех файлах, кроме `UI/Shop.luau` и `UI/Spin.luau` (файлы дизайнера, см. ниже). Все `tests/*.luau` через lune зелёные: actors, aim, balance, duel, economy, flow, hello, looks (34), net, parity, party, pay (27, новый), profile (407), receipt (125), render, server, tutor (262), ui. `trace` и `tune` — инструменты, отрабатывают.

## Исправлено

| # | Severity | Где | Что было | Что сделано | Тест |
|---|---|---|---|---|---|
| 1 | High | `src/server/Logic/Receipt.luau:180` | Чек шара за Robux, когда выбранный шар уже получен (рулетка, уровень, VOID) или выбора нет, возвращал `later` навсегда: Robux висят как NotProcessedYet. | Выдаётся выбранный шар, если его ещё нет; иначе кристаллы по цене тира (`PRICE.crystals`), `PurchaseGranted`. Выбор другого тира не трогается. Двойной выдачи нет: PurchaseId запоминается. | `tests/receipt` |
| 2 | High | `src/server/Profiles.luau:561`, `src/server/Logic/Pay.luau` | `Profiles.chooseRobux` никто не вызывал: выбрать шар или эпик для стартового набора было нечем, клиент открывал окно оплаты сам (`UI/Shelf.luau:478`), в том числе для уже купленного. | Новое действие `pay` (`Net.Action.pay`, `Lobby.luau`): клиент присылает ключ, сервер решает и сам вызывает `PromptProductPurchase`/`PromptGamePassPurchase`. Купленный облик, имеющийся шар, второй стартовый набор, купленный пасс и Fast Spin под запретом → окно не открывается, клиенту `refused = {key, why}`. Шар и эпик набора запоминаются здесь. | `tests/pay` |
| 3 | High | `src/server/Logic/Receipt.luau:166,193` | Чек уже купленного облика и второго стартового набора брал Robux и ничего не давал. | Если чек всё же пришёл — кристаллы по курсу малого пака (49 R$ → 50). Стартовый набор с уже имеющимся эпиком — набор + цена эпика кристаллами. | `tests/receipt` |
| 4 | High | `src/server/Logic/Looks.luau:95` | `Looks.repair` удалял id, которых нет в каталоге: переименование облика стирало купленное, в том числе за Robux. | Неизвестный id остаётся у игрока (снимается только с «надето»), таблица `Looks.RENAMED` старый→новый, дубли после переименования схлопываются. Витрина (`snapshot`) отдаёт только id каталога. Лимит сохраняемых обликов в `Meta.read` 40 → 64. | `tests/looks` |
| 5 | High | `src/server/Passes.luau` (новый), `init.server.luau:67` | `Products.passes` никто не читал, `pass2x = false` захардкожен. | `UserOwnsGamePassAsync` при входе (3 попытки), `PromptGamePassPurchaseFinished` для покупки в сессии, `Passes.has`. x2 монет за матч подключён. В профиле `passes` (что куплено) и `passOffer` (что можно предложить; Fast Spin нет при запрете платного рандома или неизвестной политике), `starterBought`. | `tests/pay`, `tests/profile` |
| 6 | Medium | `src/server/Profiles.luau:89` | PolicyService: неудачный ответ кешировался как «разрешено» (fail-open) на всю сессию в живом сервере. | Fail-closed в живом сервере (в Studio открыто), 3 попытки. Профиль уходит сразу со скрытыми рулетками, после ответа — ещё раз. | `tests/profile` |
| 7 | Medium | `src/server/Profiles.luau:148` | `Profiles.send` мог уйти в `GetPolicyInfoForPlayerAsync` (yield в каждом обработчике remote до первого ответа; параллельные запросы). После выхода игрока результат записывался в `paidRandomBlocked[player]` — утечка ключа Player. | `send` и `spin` читают только кеш; запись в кеш только пока профиль игрока жив. | `tests/profile` |
| 8 | Medium | `src/server/Profiles.luau:544` | `Profiles.commit` при идущем автосохранении сразу возвращал false → ProcessReceipt отвечал NotProcessedYet, хотя выдача уже в памяти. | Ждёт конец текущего сохранения до 10 с, затем пишет. | — (Store в mock) |
| 9 | Low | `src/shared/Economy.luau:83` | Бейдж «лучшая ценность» на паке 650 (1,30 кр/R$), хотя у 1400 и 3750 больше. | `best = true` на 3750 (1,50 кр/R$). Клиент бейдж пока не рисует. | `tests/pay` |
| 10 | Low | `src/client/UI/Wallet.luau:209` | Киоск магазина открывал последнюю вкладку, в том числе SPIN при запрете платного рандома. | Под запретом киоск открывает BALLS. | — |

## Проверено, в порядке

- **Покупка шара** (`Logic/Shop.luau`): id, валюта, тир, владение проверяются, цена и скидка шара дня — сервера, списание через `Wallet.spend` (без минуса, NaN → 0).
- **Рулетка** (`Logic/Spin.luau`): клиент шлёт только валюту, исход и шар — сервер, списание до броска, гарантия, отказ при запрете.
- **Косметика** (`Logic/Looks.luau`): id из каталога, повтор не списывает, продаётся при любом числе шаров, матч её не читает.
- **Вехи** (`Logic/Daily.luau`): д14 4000, д21 4000+50, д28 6000, д35 6000+50, д42 8000 (`Economy.MILE`), по `loginDays` — один раз, серия не сбрасывается.
- **Дуэль с киоска** (`UI/Plaza.searchDuel`): то же действие `queue`/`pplay`, сервер проверяет как раньше.
- **Remote**: `Action` по-прежнему за `Guard.take` (токен-бакет) и `Guard.action` (verb из таблицы, arg конечное число); третий аргумент проверяет каждый обработчик сам.
- **ProcessReceipt** (`Receipts.luau`): один, PurchaseId хранится в профиле до `PurchaseGranted`, `PurchaseGranted` только после записи.
- **Миграции** (`Meta.read`): новые поля профиля читаются с границами и типами, старая запись получает значения по умолчанию.
- **Звук удара** (`Render/Sfx.luau`): `hit` не чаще 4 раз в секунду (окно 1 с), закраска клетки без звука.
- **Соединения**: кнопки Wallet пересоздаются вместе с `ClearAllChildren` (соединения уходят с экземплярами), `PromptTriggered` подключается один раз.

## Не исправлено (файлы дизайнера или вне задачи)

| Severity | Где | Что |
|---|---|---|
| High | `src/client/UI/Shelf.luau:478` | Клиент сам вызывает `PromptProductPurchase` (в том числе для купленного облика). Перевести на `ctx.act(Net.Action.pay, nil, lookId)`; для шара за Robux — `("pay", e, "ball")`, набора — `("pay", epic, "starter")`, паков — `("pay", i, "pack")`, пассов — `("pay", nil, "pass_<key>")`. Ответ отказа — `v.refused`. |
| Medium | `src/client/UI/Shop.luau:388` | Вкладка SPIN есть всегда; при `v.spin.ok == false` по решению пользователя её нужно прятать (Wallet уже прячет кнопку SPIN и закрывает вкладку). |
| Low | `src/client/UI/Shop.luau:408`, `UI/Spin.luau:77,501,503` | Ошибки типов `luau-lsp` (Tab как string, Sfx как nil, unknown). |
| Low | `src/client/UI/init.luau:410` | `BTHold` (отладка снимков) хранит только последний профиль: разовые поля прошлых (`gains`, `claim`, `spinResult`) теряются. Только отладка. |
| Low | `src/server/Profiles.luau` (save) | После успешной записи `dirty = false`, даже если данные менялись во время yield. Сейчас безопасно: `commit` пишет сам, автосохранение идёт по `soon`/таймеру, а не по `dirty`. |

## Не сделано по указанию (перечислить)

- x10 кристальной рулетки (`price10`).
- Драфт дуэли: «Новые 3», платный «Любой шар» (лимит 2), проба. «Новые 3» — платное случайное: прятать при запрете PolicyService.
- 48-часовой таймер стартового набора (`starterUntil`).
- Перки пассов кроме x2 монет: VIP (+1 бесплатный «Любой шар», +1 задание, тег) и Fast Spin (без анимации) — сервер отдаёт владение в `v.passes`, логика перков не написана.

## Что проверить в Studio (tester)

- Покупка облика, шара, набора, пака и пасса через `pay`: окно открывает сервер, у купленного — отказ без окна (после переделки Shelf).
- `UserOwnsGamePassAsync` с реальными id и покупка пасса в сессии → `v.passes` обновляется.
- В Studio рулетки видны (политика открыта), x2 монет у владельца пасса.

## Хвосты (luau-coder, 2026-11-16)

`stylua` и `luau-lsp analyze` по `src` чисто (ошибок типов в Shop и Spin больше нет). Все `tests/*.luau` через lune зелёные (economy 565+, ui 2496+, pay 27, profile 407, receipt 125, looks, server, flow, net, party, tutor, actors, aim, balance, parity, render); `duel`, `trace`, `tune` — тяжёлые инструменты, отрабатывают. Studio не трогал.

| # | Что | Где | Тест |
|---|---|---|---|
| 1 | Кнопка R$ полки обликов шлёт `ctx.act("pay", nil, lookId)`; `PromptProductPurchase` в клиенте больше нет (удалены `prompt` и сервисы). | `UI/Shelf.luau` | `tests/ui` («pay: Shelf R$…») |
| 2 | Запрет платного рандома (`v.spin` нет или `ok = false`): вкладки SPIN нет (две вкладки на ту же ширину), открытая SPIN уходит в BALLS; косметика остаётся. Кнопка SPIN киоска и Fast Spin (offer) уже были скрыты сервером/Wallet. | `UI/Shop.luau` | `tests/ui` («spin policy…») |
| 3 | Типы: `Tab` в `Shop` (вычисляется явно), `playSfx` (`any`) и таблица видимости в `Spin`. Убран неиспользуемый `HEAD_H`. Вид не менялся. | `Shop`, `Spin` | analyze |
| 4a | VIP: +1 задание (4 вместо 3) — `Daily.quests(..., extra)`, докидывается и в середине дня, если пасс пришёл позже; не дублирует квест. | `Logic/Daily`, `Profiles.send` | `tests/economy` |
| 4b | VIP: золотое имя и `[VIP]` на плашке матча (`Seat.vip` от `Passes.has`). | `Runner`, `Net`, `UI/Hud` | analyze (без Studio) |
| 4c | Fast Spin: серверный x10 (`Spin.roll10`: одна оплата, 10 прокрутов, гарантия идёт через все; монеты 10×1000, кристаллы `price10` 399), действие `spin` с `coins10`/`crystals10` только при `Passes.has fastSpin` и без запрета; клиенту `spinHits`. Клиентская лента пропускает анимацию (как reduced motion) при `v.passes.fastSpin`. | `Logic/Spin`, `Profiles.spin`, `Net`, `UI/Spin` | `tests/economy` |

### Не сделано
- **Кнопки R$ в BALLS (Shop) и паки кристаллов в Wallet не существуют в UI**: нечему идти через `pay`. Серверная часть (`pay` с `ball`, `starter`, `pack`, `pass_*`) готова и покрыта `tests/pay`. Нужен дизайнер: R$ на карточке шара, паки, стартовый набор, офферы пассов.
- **VIP «+1 бесплатный Любой шар за дуэль»**: драфта «Любой шар» нет, перк не построен.
- **Fast Spin x10: кнопки нет в UI** (нужен дизайнер); серверная часть и `spinHits` готовы, клиент пока показывает только последний исход. Тест `Profiles.spin` с пассом отсутствует (Passes в mock без MarketplaceService), логика покрыта на уровне `Spin.roll10`.
- Проверить в Studio: плашка VIP, пропуск анимации, закрытие SPIN при запрете.
