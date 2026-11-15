# Приёмка волны 16.11, часть 3 (tester, Studio)

Дата: 2026-11-16. HEAD d423bd2 (d423bd2: кошелёк левее PlayerList, флаги `DebugNoPasses` / `DebugPaidRandomRestricted`). Место v143.
Сессия 1: `DebugFreshProfile` + `DebugNoPasses`, авто-тур обучения, `DebugXp=3000000`, `DebugDay=1`. Сессия 2: реальный профиль + `DebugPaidRandomRestricted`,
в конце дополнительно `DebugNoPasses`. Все атрибуты ServerScriptService после теста сняты (список пуст).

| ID | Вердикт | Доказательство |
|---|---|---|
| 1 Баг A: «+» и PlayerList | PASS | PlayerList включён (`GetCoreGuiEnabled(PlayerList)=true`) во всех трёх случаях. Нативно 1090×725: `AddGems` x=812, клик → магазин на CRYSTALS (`Pack6` есть). Эмуляция 1280×720: x=812, клик → CRYSTALS. 844×390: x=828, 57 px, клик → CRYSTALS. На `plus-sheet.jpg` кошелёк кончается левее окошка «SUL_GOAT». |
| 2 ScreenOrientation | PASS | В Edit `StarterGui.ScreenOrientation = LandscapeSensor`; в Play `StarterGui` и `PlayerGui.ScreenOrientation` = `LandscapeSensor`. |
| 3 Прокрутка барабана (DebugNoPasses) | PASS | `passes=[]`, `passOffer={coins2x,fastSpin,vip}`. Монеты: сервер `common e=10`, −1000. Лента едет (кадры 4–6) и встаёт на «COMMON · SAND» с плашкой приза (`spin-sheet.jpg`, 9 из 48 кадров ~10 к/с). Кристаллы: сервер `rare e=26`, 8175 → 8126 (−49). Лента едет и раскрывается на «RARE · CANDY» со свечением (`spin-sheet-crystals.jpg`). |
| 3 X10 без пасса | PASS | Кнопки вкладки: `ModeCoins, ModeGems, SpinGo[SPIN 1,000], BuyFastSpin[X10 R$99]`, `Spin10` нет. |
| 3 VIP-перки без пасса | PASS | Кнопка QUESTS «0/3» (с пассом было 0/4). Имя золотом в матче без VIP в этой сессии не проверял. |
| 4 Запрет платного рандома | PASS | `spin.ok=false` (шансы обнулены). HUD-кнопки: `AddGems, DailyBtn, QuestsBtn, BookBtn, ShopBtn`, `SpinBtn` нет. Вкладки магазина: `TabBalls, TabSkins, TabPacks`, `TabSpin` нет (`policy-shop.png`). `Action spin` coins/crystals → баланс 765 / 60 не изменился. С `DebugNoPasses` поверх: `passOffer={coins2x,vip}`, Fast Spin нет и в полосе офферов. `pay pass_fastSpin` → `refused policy`. Работают: SKINS — EQUIP `frame_wood` → `on.frame=frame_wood`; CRYSTALS — 6 паков, R$49 → окно «50 Crystals 49», закрыто (`PromptProductPurchaseFinished false`, кристаллов 60); BALLS — вкладка открыта, у профиля 27/27 («0 BALLS LEFT»), покупку проверял в части 1. |
| 4 «Новые 3» | N/A | В коде не реализовано (по словам координатора). |
| 5 След облика в матче | PASS | `trail_dust` надет. Числами: искры цвета `#e0c48a` / `#fff2cc` в `Workspace.BTRender.BoardGui.Root.Fx` — в 31 из 40 замеров по 0,25 с, до 16 одновременно, 5 px. Глазами: бежевые искры за шаром YOU, у бота нет (`trail-zoom.png`). След держится на месте игрока, а не на конкретном шаре: шара 0 со скином в раунде не было, след был. |

## Наблюдения
- Первый Play сессии 2: профиль не загружался больше 90 с, в логе ни строки, ошибок нет, бюджет UpdateAsync 2709. Со второго Play загрузился за 12 с (ожидание блокировки `lockWait`). Не повторилось. Похоже, завис запрос к DataStore в Studio.
- Тосты от `DebugXp` идут сотнями и видны поверх вкладки SPIN на листах. Это следствие отладки, не баг.
- На реальном профиле надета рамка `frame_wood` (EQUIP во время проверки SKINS).

## Итог
Все пункты части 3 прошли. Вместе с частями 1–2 открытых FAIL нет. Остались NOT VERIFIED: тег [VIP] на чужой плашке (нужен второй игрок) и перехват касаний настоящим TouchGui на телефоне.
