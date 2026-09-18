# Стенд Play-проверки

Настоящая Studio, настоящий Play с игроком: сценарий ходит персонажем,
зонд пишет отчёт, окна Studio снимаются в PNG.

```bash
python tools/playtest/run.py walk     # пешком к каждому паду и в порталы
python tools/playtest/run.py shots    # снимки экрана в build/shots
python tools/playtest/run.py basic    # первые 20 секунд: где персонаж, есть ли панель
python tools/playtest/run.py run      # забег: станция и аттракционы, возврат к флажку (ZZ_ONLY=уровень)
python tools/playtest/run.py lava     # «Пол — это лава!»: верная плита, чужая, конец игры
```

- Сценарии — `scenarios/<имя>.luau`: функция `(player, note)`, снимок кадра — `_G.ZZ_Shot(player, name, cframe, fov)`.
- Плагин ставится в `%LOCALAPPDATA%\Roblox\Plugins` на время прогона и убирается после.
  В обычных местах он ничего не делает: срабатывает только по метке `ZZ_Mode` в Workspace.
- Если Studio не стартует: путь в реестре устарел после обновления — запустить и закрыть Studio один раз.

## Импорт моделей Creator Store

```bash
python tools/models/import.py tools/models/picks.json
```

Плагин берёт модель через `game:GetObjects` (владеть ею не нужно), вырезает скрипты,
MeshPart переписывает в Part + SpecialMesh (MeshPart с чужим MeshId из файла не грузится)
и пишет `assets/models/decor/<id>.model.json`.
