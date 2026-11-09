# Сцена: контракт для клиента

Сцена генерируется: `lune run tools/scene/gen` пишет `scene/Arenas.model.json` и `scene/Lobby.model.json` (Rojo). Studio вручную не правим.

Арены в `Workspace.Arenas` (Duel1..3, FFA1), в небе на y≈200, в ряд по X: −78, −26, 26 (дуэли, слоты по 52 студа), 84 (FFA, слот 64). Все доски смотрят в +Z, на площадку. Ищи по тегу CollectionService `Arena`, не по пути.
Атрибуты Model: `Mode` ("duel"|"ffa"), `GridW`, `GridH` (дуэль 16×14, ffa 24×20), `CellSize` в studs (дуэль 1.5, ffa 1.25).
Внутри: `Board` (тёмная доска), `Field` (светлый фон), `Origin` (Attachment в Board), `Rim` и неоновые `Edge*` вокруг доски, `Pedestal`, `Stand1..2` (ffa `Stand1..4`) — колонны-площадки, `Glow1..4` — неоновое кольцо у верха площадки, `Base1..4`, `Camera` (невидимый Part), `Floor`, `Edge`, неоновые `LaneFront`/`LaneBack`.

Доска вертикальная, лицо смотрит в +Z; камера на +Z смотрит в -Z. Размеры `Board`/`Field` не используй: считай по `GridW`, `GridH`, `CellSize`.

**Origin:** левый верхний угол области клеток, на лицевой плоскости `Board`. Ось i (строка) идёт вдоль `Origin.WorldCFrame.RightVector` (мир +X). Ось j (столбец) идёт вниз, вдоль `-UpVector`. Клетки с нуля: i = 0..GridW-1, j = 0..GridH-1.

**Клетка в мир (центр):**
```lua
local o = origin.WorldCFrame
local pos = o * Vector3.new((i + 0.5) * cs, -(j + 0.5) * cs, 0.1) -- 0.1 к камере, над Field
```
**Тап в клетку:** луч из камеры, плоскость через `o.Position` с нормалью `o.ZVector` (мир +Z):
```lua
local t = (o.Position - ray.Origin):Dot(o.ZVector) / ray.Direction:Dot(o.ZVector)
local p = o:PointToObjectSpace(ray.Origin + ray.Direction * t)
local i, j = math.floor(p.X / cs), math.floor(-p.Y / cs) -- вне поля: i<0, j<0, i>=gw, j>=gh
```
**Камера:** `CameraType = Scriptable` у `arena.Camera`. Клиент (`Render/Cam.luau`) вписывает доску в середину экрана между боковыми колонками (по 26 % ширины) под полосой сверху и поднимает камеру на нужную долю; FOV считается, а не 70.
**Площадки (раскладка Ball vs Ball):** персонаж стоит в `StandN.Position + (0, StandN.Size.Y/2, 0)`, место `side + 1`. Площадки стоят ближе к камере, чем доска, и по X так, что аватар попадает в центр боковой колонки экрана: дуэль `Stand1` (-14.1, z 8) слева, `Stand2` (+14.1) справа, верх на y 210.9; ffa спереди-снаружи `Stand1`/`Stand2` (∓19.2, z 10, верх 211.0), сзади-внутри `Stand3`/`Stand4` (∓16.8, z 6, верх 210.2). Клиент красит `GlowN` в цвет шара места и ставит локальный манекен на площадку бота.
**Лобби (M1.6) — площадка перед рядом арен:** `Workspace.Lobby.Pad` (y 200, x −104…116, z 30…74), `Spawn` (SpawnLocation в (0, 200, 56), лицом к аренам; сервер ставит его в `Player.RespawnLocation`, старый `SpawnLocation` у Baseplate не используется — персонажа с него сервер переносит на площадку). Неоновый `Rail` с невидимой стеной `WallFront` на z 30 не пускает к аренам: камеры матчей стоят на z 22–26, люди с площадки в кадр не попадают. Невидимые стены по краям, неоновые полосы, две колонны сзади. Зритель стоит в 30–75 студах от доски.
