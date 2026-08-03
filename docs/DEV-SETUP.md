# DEV-SETUP — как запустить проект

## 1. Инструменты

Ставим менеджер инструментов [Rokit](https://github.com/rojo-rbx/rokit), дальше он поставит всё сам:

```bash
rokit install
```

Это даст `rojo`, `stylua`, `selene`, `luau-lsp`, `run-in-roblox` нужных версий (см. `rokit.toml`).
Если у тебя уже стоит Aftman — те же строки работают в `aftman.toml`.

Зависимости Luau ставятся через [Wally](https://wally.run):

```bash
wally install
```

Появятся папки `Packages/` и `DevPackages/` — они в `.gitignore` и в репозиторий не идут.

## 2. Запуск в Roblox Studio

```bash
rojo serve
```

В Studio: плагин Rojo → **Connect**. Дальше правим файлы в редакторе, Studio обновляется сам.

Собрать место в файл:

```bash
rojo build -o build/AlphabetFall.rbxl
```

## 3. Тесты

```bash
rojo build test.project.json -o build/test.rbxl
```

```bash
run-in-roblox --place build/test.rbxl --script tools/TestRunner.server.luau
```

Что покрыто:

| Файл | Что проверяет |
|---|---|
| `tests/MasteryRules.spec.luau` | переходы статусов буквы, правило «через 2 дня», отсутствие понижения |
| `tests/ReviewScheduler.spec.luau` | интервалы повторения и сборка очереди сессии |
| `tests/DifficultyCurve.spec.luau` | адаптивная сложность и потолок |
| `tests/ConfigIntegrity.spec.luau` | инварианты контента: слова из выученных букв, слоги, озвучка |

`ConfigIntegrity` — самый важный: он ловит ошибки, которые иначе всплывут на ребёнке
(слово из невыученных букв, слог без записи, ссылка на несуществующее испытание).

## 4. Стиль и линт

```bash
stylua src tests tools
```

```bash
selene src tests tools
```

## 5. Структура

```
src/shared    → ReplicatedStorage.Shared    конфиги, чистая логика, типы, Remote-реестр
src/server    → ServerScriptService.Server  источник истины: прогресс, экономика, испытания
src/client    → StarterPlayerScripts.Client презентация: звук, UI, ввод
tests         → ReplicatedStorage.Tests     только в test.project.json
tools         → утилиты разработки, в прод-сборку не попадают
```

Полное описание архитектуры — [07-TECH-ARCH.md](07-TECH-ARCH.md).

## 6. Что сделано и что дальше

**Готово:**
- Rojo-скелет, линтеры, Wally.
- `Config/Letters` — 9 букв MVP (А У О И · М П Б · Т Н) со звуками, цветами и парами-путаницами.
- `Config/Syllables` — слоги генерируются из букв, с запретом ЖЫ/ШЫ/ЧЫ/ЩЫ/ЦЫ.
- `Config/Words` — 8 слов MVP; `Config/Islands` — первые 3 острова.
- `Config/Challenges`, `Config/Economy` — все числа вынесены из кода.
- `Config/AudioRegistry` — реестр озвучки; пока пустой, игра это переживает и пишет в лог.
- `Logic/MasteryRules`, `Logic/ReviewScheduler`, `Logic/DifficultyCurve` — чистые, с тестами.
- `Net/RemoteDefs` — единый реестр Remote'ов с лимитами частоты.
- `AudioController` — очередь озвучки, приглушение музыки на время реплики, кнопка «повторить».

**Дальше (веха 1, см. [12-ROADMAP.md](12-ROADMAP.md)):**
1. `ProfileService` — сохранение с session-lock и миграциями.
2. Испытание «Буквопад» целиком: сервер строит задание, валидирует, начисляет.
3. `ProgressService` + `EconomyService`.
4. Хаб, Башня, магазин на 12 предметов.
5. Запись первых 60 реплик озвучки и заполнение `AudioRegistry`.
