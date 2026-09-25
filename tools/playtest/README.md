# Стенд Play-проверки

Настоящая Studio, настоящий Play с игроком: сценарий ходит персонажем,
зонд пишет отчёт, окна Studio снимаются в PNG.

```bash
python tools/playtest/run.py walk     # пешком к каждому паду и в порталы
python tools/playtest/run.py shots    # снимки экрана в build/shots
python tools/playtest/run.py basic    # первые 20 секунд: где персонаж, есть ли панель
python tools/playtest/run.py run      # забег: станция и аттракционы, возврат к флажку (ZZ_ONLY=уровень)
python tools/playtest/run.py lava     # «Пол — это лава!»: верная плита, чужая, конец игры
python tools/playtest/run.py styles   # форма и краска построек: окна дома, вторые вещи наборов, экран выбора
python tools/playtest/run.py tour     # уровень пути сверху: что стоит по порядку, снимки кусками (ZZ_ONLY=уровень)
python tools/playtest/run.py ui       # задания дня, тост, экран итогов, магазин поверх HUD
python tools/playtest/run.py wardrobe # вещи магазина на персонаже (ZZ_ONLY=hat_cap,face_glasses)
ZZ_ONLY="607702162:8" python tools/playtest/run.py tryon  # кандидаты из каталога Roblox на манекенах
```

- Долгий прогон — `ZZ_WAIT=600`: сценарий в Studio сам оборвётся за 20 с до этого срока.
- Клиент Studio в фоне даёт кадр раз в несколько секунд: всё, что двигает клиент
  (вертушки, облака), в стенде может стоять. Сверять надо не «сдвинулось ли»,
  а «где должно быть» — `ZZ_Inspect` у движущейся детали пишет и то и другое.

- Сценарии — `scenarios/<имя>.luau`: функция `(player, note)`, снимок кадра — `_G.ZZ_Shot(player, name, cframe, fov)`.
- Плагин ставится в `%LOCALAPPDATA%\Roblox\Plugins` на время прогона и убирается после.
  В обычных местах он ничего не делает: срабатывает только по метке `ZZ_Mode` в Workspace.
- Если Studio не стартует: путь в реестре устарел после обновления — запустить и закрыть Studio один раз.

## Аксессуары каталога Roblox

```bash
python tools/models/catalog.py "flower crown" "cat ears" [--roblox]
```

Ищет бесплатные аксессуары, пишет `build/catalog/candidates.json`. Миниатюры CDN
Roblox отсюда не грузятся — смотреть вещи на манекене сценарием `tryon`.

## Импорт моделей Creator Store

```bash
python tools/models/import.py tools/models/picks.json
```

Плагин берёт модель через `game:GetObjects` (владеть ею не нужно), вырезает скрипты,
MeshPart переписывает в Part + SpecialMesh (MeshPart с чужим MeshId из файла не грузится)
и пишет `assets/models/decor/<id>.model.json`.
