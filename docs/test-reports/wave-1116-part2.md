# Приёмка волны 16.11, часть 2 (tester, Studio)

Дата: 2026-11-16. HEAD 5305234 (e7519ef баги 2–5,7, 856196b витрина Robux, 5305234 облик в матче). Studio b6b33902…, три сессии Play.
Сессия 1: `DebugFreshProfile` + авто-тур обучения + `DebugXp=3000000` (L2732, 408 450 монет) + `DebugDay=1` (новый шар дня).
Сессия 2: реальный профиль, только замеры на 844×390. Отладочные атрибуты после теста сняты.
В Studio владелец владеет всеми тремя геймпассами (`passes={coins2x,fastSpin,vip}`), отладочного флага для геймпассов и PolicyService в коде нет.

| ID | Вердикт | Доказательство |
|---|---|---|
| 1 Облик в матче | PASS (след NOT VERIFIED) | Куплены и надеты `skin_ink` (на шар 0 FIRE), `trail_dust`, `force_pulse`, `frame_wood`: 408 450 → 398 450 (−10 000 = 2500+2500+3000+2000), `on={skin:skin_ink, ball:0, trail, force, frame}`. Дуэль с ботом шаром 0: шар YOU тёмный с белым крапом (INK), у бота TIME/GLITCH обычные (`match-looks.png`, `match-looks-sheet.jpg`). Рамка: коричневое кольцо вокруг портрета YOU, у BOT обычное (`match-looks-zoom.png`). Сила: `Input power` → вокруг шара кольцо при IGNITE (кадры 3–4 листа). След: частиц `trail_dust` на снимках 800 px не разобрать — NOT VERIFIED глазами (код `Wear.update` пускает искры за движущимся шаром). |
| 2 Музыка (баг 3) | PASS | Обучающий матч: `music=false`, `musicMatch=true` (pos 11.7 → 35.1). После выхода на площадку: `music=true` (pos 26.8), `musicMatch=false`. Дуэль: `music=false`, `musicMatch=true`. Одновременно всегда играет один трек. |
| 3 STICK/JUMP (баг 4) | PASS | `GuiService.TouchControlsEnabled`: в матче false, с открытой ежедневной наградой false, с открытым магазином false, на площадке без окон true. Замечание: заглушки STICK/JUMP в эмуляции `BTEmulate` рисуются всегда и за флагом не следят (`phone-shop-part2.png`). Это вводит в заблуждение только в отладке. |
| 3 PlayerList (баг 5) | PASS, но новый баг | Магазин или награда открыты → `PlayerList=false`, площадка → true. **Новый баг:** на площадке окошко PlayerList лежит прямо на кнопке «+» кристаллов в HUD и съедает нажатие: 2 клика по `Wallet.Frame.AddGems` ничего не открыли, после `SetCoreGuiEnabled(PlayerList,false)` тот же клик открыл CRYSTALS (`hud-plus-under-playerlist.png`). |
| 3 Тосты (баг 2) | PASS | Три тоста одновременно: y = 155 / 194 / 232, текст читается («LEVEL 13…», «LEVEL 14…», «LEVEL 15… +15 CRYSTALS»). |
| 3 Ориентация (баг 7) | FAIL в Studio / PASS в проекте | `default.project.json` → `StarterGui.ScreenOrientation = "LandscapeSensor"`, но в открытом месте `StarterGui.ScreenOrientation = Sensor` и `PlayerGui.ScreenOrientation = Sensor`: живой Rojo свойства сервиса не применил. Нужно применить в Studio (или пересобрать или переподключить Rojo) и сохранить и опубликовать место, иначе в живой игре портрет останется. |
| 3 Цели ≥44 px (баг 6) | PASS | 844×390, px телефона: табы BALLS/SPIN/SKINS/CRYSTALS 158×44, Close магазина 52×52, «+» 44×44, Close награды 46×46, HUD SPIN 57×57. |
| 4 R$ на шарах | PASS | Шар дня LIGHT (epic, 4200 / 140 / R$199) → окно Roblox «Buy item: Epic Ball, 199, test purchase» (`robux-prompt.png`). Обычный EARTH R$49 → «Buy item: Common Ball 49» (видно в CoreGui). Закрыто крестиком: `PromptProductPurchaseFinished(3732004545, false)`, шаров 13 → 13. Пока открыто одно окно, второй клик R$ ничего не открывает (так ведёт себя Roblox). |
| 4 CRYSTALS | PASS | Вкладка: 6 паков 50/110/300/650/1400/3750, R$49…R$2499, бонусы +9…+47%, `BEST VALUE` только на 3750, плюс оффер STARTER R$99. «+» в шапке магазина (`AddGems` 70×70) и «+» в HUD открывают CRYSTALS (HUD — только без PlayerList, см. выше). |
| 4 X10 | PASS (без пасса NOT VERIFIED) | С Fast Spin: кнопка `Spin10` «X10 10,000»; 10 исходов (4 common, 4 refund, rare, epic); 398 450 − 10 000 + 1000 возвратов = 389 450. Повторная покупка пасса: `pay pass_fastSpin` → `refused owned`. Без пасса по коду (`UI/Spin.luau:478-525`) вместо X10 стоит `BuyFastSpin` «X10 R$…» → `pay pass_fastSpin`, сервер `Profiles.spin` отказывает `coins10` без пасса. Живьём не проверить: пасс у владельца. |
| 4 Прокрутка барабана | NOT VERIFIED | Fast Spin у владельца показывает итог без прокрутки, отладочного флага нет. Новый `spin-sheet.jpg` не снимал: анимации нет. |
| 5 Запрет платного рандома | NOT VERIFIED (код OK) | Отладочного флага политики нет, в Studio PolicyService разрешает. По коду при `spin.ok=false`: нет вкладки SPIN (`Shop.luau:614-698`), нет HUD-кнопки SPIN (`Wallet.luau:328`), X10 и BuyFastSpin живут только во вкладке SPIN, `Pay.offer` отказывает fastSpin с `policy`, `passOffers` не предлагает Fast Spin. SKINS и CRYSTALS без условия. «Новые 3» в клиенте по имени не найдено, уточнить, что это. |
| 6 Shelf R$ / повтор | PASS | `Shelf.luau:723-728`: PayRobux → `Action pay` (сервер выбирает product id). `pay skin_ink` при владении → `refused owned`, `pay bogus` → `bad`. Повторная покупка за монеты `look skin_ink` / `frame_wood` → баланс 398 450 не изменился. |
| 7 VIP | PASS частично | Своё имя «YOU» в HUD жёлтое `#ffd63c` (VIP) вместо цвета места `#40baff`. Заданий 4 («0/4» на кнопке QUESTS, база 3 + 1 VIP). Тег `[VIP] NAME` показывается только на чужой плашке (`Hud.nameOf`), в одиночку не проверить — NOT VERIFIED. |

## Баги

**A. «+» кристаллов в HUD не нажимается: его перекрывает PlayerList.** Серьёзность: важно (главный вход в покупку кристаллов).
Шаги: площадка, окна закрыты, нажать «+» у кристаллов справа сверху. Ожидалось: магазин на CRYSTALS. Получилось: ничего; с выключенным PlayerList открывается.
Вероятное место: `UI/Wallet.luau` (позиция кошелька под окошком PlayerList справа сверху) — сдвинуть кошелёк ниже/левее или держать PlayerList скрытым на площадке.

**B. ScreenOrientation в месте всё ещё Sensor.** Серьёзность: важно. Свойство есть только в `default.project.json`, живой Rojo его не применил.
Нужно выставить `StarterGui.ScreenOrientation = LandscapeSensor` в месте и опубликовать.

**C. Заглушки STICK/JUMP в эмуляции не следят за `TouchControlsEnabled`.** Серьёзность: мелочь, только отладка (`UI/init.luau:54-68`).

## Не проверено
- Прокрутка барабана и X10 без Fast Spin: все пассы у владельца в Studio. Нужен отладочный атрибут, отключающий пасс, или аккаунт без пасса.
- Скрытие под запретом платного рандома: нет отладочного флага PolicyService (проверено по коду).
- Тег [VIP] на чужой плашке: нужен второй игрок.
- След `trail_dust` глазами: искры мелкие, на снимках не видны.
- Во время серии кадров на экране дважды мелькнул переключатель приложений macOS (кадры 3–4 `match-looks-sheet.jpg`).

## Итог
Баги 1–7 из части 1 закрыты в коде, кроме ориентации: место в Studio всё ещё Sensor. Витрина Robux работает через сервер.
Принимать можно после двух правок: «+» в HUD под PlayerList (A) и ScreenOrientation в месте (B). Прокрутку и политику проверить на аккаунте без пассов или с отладочным флагом.
