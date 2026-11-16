# Лицензии картинок

| Ассет | Roblox id | Источник | Лицензия |
|---|---|---|---|
| HUD: подарок (DAILY) | rbxassetid://79399567920096 | своя работа, SVG `tools/art/hud/icons.html` → `assets/art/hud/daily.png` (`node tools/art/hud/render.mjs`) | своя, CC0 |
| HUD: свиток (QUESTS) | rbxassetid://134446016241479 | то же, `quests.png` | своя, CC0 |
| HUD: книга (BOOK) | rbxassetid://107518731338758 | то же, `book.png` | своя, CC0 |
| HUD: лавка (SHOP) | rbxassetid://115317288173478 | то же, `shop.png` | своя, CC0 |
| HUD: кучка монет (счётчик) | rbxassetid://96009887810654 | то же, `coins.png` | своя, CC0 |
| Атласы шаров, земли, иконок (`src/shared/Art.luau`) | см. Art.luau | свой веб-билд ball_territory_web, `tools/art/export.mjs` | своя |

## Модели сцены (S-1, Creator Store, бесплатные; лежат в `ServerStorage.DecorKit`, копии в `Workspace.Decor`, вне Rojo)

| Модель | Asset id | Автор | Лицензия / проверка |
|---|---|---|---|
| Low Poly Tree - Cartoon (деревья) | 13870570014 | lukabricks | бесплатная модель Creator Store; 2 MeshPart, скриптов нет |
| Low Poly Tree (ели) | 12549617200 | Remadex Development | бесплатная модель Creator Store; 2 MeshPart + Weld, скриптов нет |
| Floating Island (дальние острова) | 16519830532 | Starblaze Games | бесплатная модель Creator Store; 209 частей, скриптов нет, SpawnLocation удалён |
| Awesome Crystal Cluster Mesh (кристаллы стихий) | 157006174 | XenoSynthesis (меш из гира Roblox Korblox Tripmine) | бесплатная модель Creator Store; 1 Part + SpecialMesh, скриптов нет |
| Low Poly Rock Pack (камни) | 92982472852108 | Swiftspin3305 (внутри подпись «by FracturedSkies» — вероятно перезалив) | бесплатная; **внутри были Script, LocalScript, RemoteFunction и скрытый ScreenGui — удалены, оставлены только 10 MeshPart**. Заменить на свои камни перед запуском, если важна чистота авторства |

Остальная геометрия (острова, ворота, рамки, постаменты, медальоны) — своя, `tools/scene/gen.luau`. Небо — стандартный скайбокс Roblox `rbxasset://textures/sky/sky512_*`.
