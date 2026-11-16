# Звуки (переподбор A-2, 2026-11-16)

Пользователь: «звук такое говно». Самодельные синтезированные звуки (sfx_capture/power/reaction/final/win, id в старой таблице ниже, раздел «Прежние») заменены на бесплатные лицензированные звуки Creator Store (Audio → Sound Effects): Roblox (официальные) и APMOfficial (Courtesy of APM Music). Лицензия Creator Store: бесплатно во всех играх Roblox, загрузка в наш аккаунт не нужна и не делалась. Нормализации громкости под рукой нет (файлы не скачиваются без cookie Roblox), поэтому баланс задаётся `Volume` в `src/client/Render/Sfx.luau`, а длинные стинги обрезаются полем `cut` (затухание 0,12 с и Stop).

**НА СЛУХ НЕ ПРОВЕРЕНО.** Выбор по названию, описанию APM и жанру. Длины у большинства не указаны, `cut` страхует. Слушать в Play: hit, power, reaction, final, win, rare, epic, legend. Если ассет молчит, подставить запасной из таблицы (одна правка id).

| Cue | Где играет | id | Название и источник | Лицензия | Запасной | Volume / cut |
|---|---|---|---|---|---|---|
| hit | столкновение шаров и KO, ≤4 в секунду | 16480568432 | Roblox_Pinball_Bumper_Soft_Click_03 (Roblox) | Creator Store, free | 16480567946 Bumper_Weighted_Click_01 | 0.5 / 0.5 с |
| power | срабатывание силы | 1839901345 | «Powered Up Chimes», Juice Music, 5 с (APM) | Creator Store, free, APM | 16480579431 8Bit_Blip_05 | 0.5 / 1.1 с |
| reaction | любая реакция | 108306323478967 | «Whoosh Magic Spell» (APM) | то же | 15675046931 Roblox_UI_Sweep | 0.7 / 1.3 с |
| final | начало финала | 1837769225 | «Retro Gamer (sting)», Skip Armstrong, альбом CHIPTUNE, как музыка (APM) | то же | 1840000886 «End Game (sting)», 7 с | 0.7 / 2.4 с |
| win | победа | 1836473422 | «Victory Fanfare Sting» (APM) | то же | 1844259840 «Glorious Victory Link 1» | 0.75 / 3.5 с |
| rare | остановка ленты на rare | 16480578737 | Roblox_Pinball_8Bit_Blip_07 (Roblox) | Creator Store, free | 16480578302 8Bit_Blip_10 | 0.5 / 0.8 с |
| epic | остановка ленты на epic | 1846251193 | Jackpot Mania «Win», 3 с (APM, Sonoton) | то же | 1844259840 | 0.6 / 2 с |
| legend | остановка ленты на legend | 1846251212 | Jackpot Mania «Star Prize», 6 с (APM) | то же | 1837762472 «Victory Dance (sting a)» | 0.7 / 3.2 с |
| click | клик любой кнопки UI (`Theme.press` → `Theme.sfx`) | 15675059323 | Roblox_UI_Bright_Click (Roblox) | Creator Store, free | 15675032796 Small_Click | 0.3 |
| tick | тик рулетки: каждая карточка под маркером (Spin) | 16480580213 | Roblox_Pinball_8Bit_Blip_01 (Roblox) | то же | 16480580064 Blip_02 | 0.25 / 0.25 с |
| coin | рост счётчика монет (`Money.step`), ≤8 в секунду | 127645268874265 | CoinTransfer_01 (Roblox) | то же | 16480570986 Bumper_Low_Bells_02 | 0.3 / 0.5 с |
| music | лобби | 1837768352 | «Retro Gamer (a)», Skip Armstrong (APM), 2:12 | то же | 1837351107 «Rainbow Road» | 0.20 |
| musicMatch | свой матч | 1837768494 | «Battle Hero (a)», Skip Armstrong (APM), 1:59 | то же | 1837768323 «Final Boss (a)» | 0.14 |

Музыку не менял: оба трека уже яркие chiptune APM из того же альбома, что и стинг final. Заметные альтернативы лобби при желании: «Rise to the Top (a 15)» 1837769983 (POP BREAKS, 15 с) не подходит как луп; других лучше найденных нет.

Закраска клеток по-прежнему молчит (решение пользователя).

Нашёл через `apis.roblox.com/toolbox-service/v1/marketplace/3` (поиск) и `economy.roblox.com/v2/assets/<id>/details` (автор, описание). Брал только создателей Roblox и APMOfficial: у остальных SoundEffect-загрузок лицензия сомнительна (например «retro coin pickup» с пометкой «credits to LilMati on freesound»). Своих CC0-загрузок не делал.

## Прежние (до A-2, оставлены как запасной вариант)

Синтез из WebAudio веба (`assets/audio/src/synth.py`), загружены 2026-11-09 в SUL_GOAT: hit/capture 84349985737198, power 126093538007975, reaction 124991616061855, final 79742001226121, win 82466908590237.

**F1 (2026-11-10):** звук закраски клеток убран — он звучал до 8 раз в секунду и на слух «постоянно пукал». Закраска по-прежнему молчит. С 2026-11-11 тот же ассет `sfx_capture` играет как `hit`: столкновение шаров (`bump`) и KO, не чаще 4 раз в секунду. Урон оружием (`hit` в правилах) остаётся только картинкой. Сила, реакция, финал и победа не менялись.

**Тиры (2026-11-11):** отдельных файлов нет. `rare`, `epic`, `legend` — вторые Sound на уже залитых id power, reaction и win. У них свои Volume и PlaybackSpeed, поэтому исходные power / reaction / win звучат как раньше. Дизайнер вызывает `Sfx.play("rare" | "epic" | "legend")` на остановке ленты. Это не новые ассеты.

**Музыка (2026-11-16):** своего трека нет, взяты бесплатные лицензированные треки Roblox из Creator Store (Audio → Music), автор загрузки APMOfficial (верифицирован), исполнитель Skip Armstrong, альбом CHIPTUNE, «Courtesy of APM Music». Ссылки: https://create.roblox.com/store/asset/1837768352 (лобби) и https://create.roblox.com/store/asset/1837768494 (матч). Лицензия: бесплатные аудио Creator Store разрешены во всех играх Roblox, загрузка в наш аккаунт не нужна и не делалась. Проверка доступа 2026-11-16: `toolbox-service` details — `isFree: true`, `visibilityStatus: 0`, `isAssetHashApproved: true`; assetdelivery отдаёт 200 под аккаунтом SUL_GOAT. Проверку чекером прав universe 10775439626 API отклонил (XSRF), поэтому финально проверьте на слух в Play; если звук молчит, это единственное место для сомнения. `Sfx.plaza(false)` играет лобби-трек, `Sfx.plaza(true)` (свой матч) останавливает его и играет матчевый. Громкость музыки (0.20 и 0.14) ниже любого эффекта (минимум 0.35).

Запасные кандидаты (тот же источник, тоже бесплатные APM, 2:00+): «Final Boss (a)» 1837768323 (2:11, Skip Armstrong) на матч; «Rainbow Road» 1837351107 (2:39, Gum Motion Tracks) на лобби. Короткие 60-секундные версии: «Retro Gamer (60)» 1837769001, «Final Boss (60)» 1837768943.

Громкость: все файлы нормализованы одинаково (пик −1,5 дБ), баланс задаётся свойством `Volume` в игре. Значения — стартовые, подстройте на слух.

## Как загрузить (Creator Hub)
1. Откройте https://create.roblox.com/dashboard/creations и войдите под аккаунтом-владельцем игры (или группы, если игра в группе).
2. Выберите Development Items → Audio → Upload Asset (в Studio то же: Asset Manager → Audio → Bulk Import).
3. Выберите файлы `assets/audio/sfx_*.ogg` (если `.ogg` не принят, берите `.wav`). Проверка модерации занимает до нескольких минут.
4. Дождитесь статуса Accepted. Откройте каждый звук и скопируйте Asset ID (число из адреса).
5. Впишите ID в пустую колонку таблицы и передайте файл координатору: luau-coder внесёт их в модуль `SoundIds`.
6. Владелец звука и игры должен совпадать. Для групповой игры загружайте от имени группы.
