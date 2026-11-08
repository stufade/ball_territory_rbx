# Сцена M1: контракт для клиента

Арены в `Workspace.Arenas` (Duel1..3, FFA1), в небе на y≈200, по X через 300 студов. Ищи по тегу CollectionService `Arena`, не по пути.
Атрибуты Model: `Mode` ("duel"|"ffa"), `GridW`, `GridH` (дуэль 16×14, ffa 24×20), `CellSize` в studs (дуэль 1.5, ffa 1.25).
Внутри: `Board` (тёмная рамка), `Field` (светлый фон), `Origin` (Attachment в Board), `Stand1..2` (ffa `Stand1..4`), `Camera` (невидимый Part), `Floor`.

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
**Камера:** `CameraType = Scriptable`, `Camera.CFrame = arena.Camera.CFrame`, FOV 70. Рассчитано на горизонтальный телефон (около 2:1).
**Площадки:** персонаж стоит в `StandN.Position + (0, StandN.Size.Y/2, 0)`. Дуэль: Stand1 слева, Stand2 справа. ffa: Stand1, Stand3 слева; Stand2, Stand4 справа (Stand3/4 дальше от камеры).
**Лобби:** `Workspace.Lobby.Pad` у `SpawnLocation`.
