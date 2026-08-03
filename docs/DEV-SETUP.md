# DEV-SETUP — как запустить проект

## 0. Что нужно установить (Windows)

**Минимум, чтобы увидеть игру:**

1. **Roblox Studio** — сама среда, где всё запускается. Нужен аккаунт Roblox.
   ```
   winget install --id Roblox.RobloxStudio
   ```
2. **Rojo** — синхронизирует файлы из репозитория в Studio.
   ```
   winget install --id Rojo.Rojo
   ```
3. **Плагин Rojo для Studio** — ставится самой Rojo одной командой:
   ```
   rojo plugin install
   ```

**Дополнительно (для тестов и удобства):**

- **Rokit** (`winget install --id Rojo.Rokit`) — менеджер инструментов: поставит `wally`,
  `stylua`, `selene`, `luau-lsp`, `run-in-roblox` нужных версий одной командой `rokit install`.
  Если ставишь Rokit, отдельная установка Rojo не нужна — он придёт из `rokit.toml`.
- **VS Code** + расширения **Luau Language Server** и **StyLua**.

## 1. Инструменты через Rokit

```bash
rokit install
```

Ставит всё из `rokit.toml`. Если Rokit ругается, что версии нет, — обнови её
командой `rokit add <имя-инструмента>`.

Зависимости Luau (нужны только для тестов — там лежит TestEZ):

```bash
wally install
```

Появятся папки `Packages/` и `DevPackages/` — они в `.gitignore` и в репозиторий не идут.
Для запуска самой игры они не требуются.

## 2. Запуск в Roblox Studio

```bash
rojo serve
```

В Studio: открыть любое пустое место (Baseplate), вкладка **Plugins** → **Rojo** → **Connect**.
Дальше **Play** — и правим файлы в редакторе, Studio обновляется сам.

**Про сохранения:** без публикации места DataStore недоступен, и профиль работает
в памяти — прогресс не переживёт перезапуск, это ожидаемо и в логе об этом написано.
Чтобы сохранения заработали по-настоящему: опубликовать место
(File → Publish to Roblox) и включить Game Settings → Security → **Enable Studio Access
to API Services**.

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
| `tests/Migrations.spec.luau` | миграции профиля, достройка полей, срез для клиента |
| `tests/Economy.spec.luau` | награды за переходы статусов, гарантированный минимум, тиры цен |
| `tests/LetterRain.spec.luau` | построение задания, валидация тапов, устойчивость к мусору от клиента |

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

- Слой данных: `DataBackend` (DataStore с сессионной блокировкой и ретраями, в Studio —
  память), `ProfileService` (загрузка, автосохранение раз в минуту, выгрузка, BindToClose),
  `ProfileTemplate` + `Logic/Migrations` с тестами.
- `EconomyService` — единственная точка начисления Звёздочек, с часовым потолком
  и белым списком источников.
- `ProgressService` — применение ответов: статусы букв, планирование повторений,
  открытие островов, адаптивная сложность, заказ наград.

- `ChallengeService` + `Challenges/LetterRain` — испытание «Буквопад» целиком:
  сервер строит задание, валидирует каждый тап по своему времени, начисляет награду.
- `RateLimiter` — лимиты частоты на Remote'ы.
- Клиент: `ChallengeController` (падающие буквы без физики, тапы, обратная связь)
  и серый HUD (счётчик ⭐, буква-цель, кнопка «динамик»).

**Как проверить руками:** `rojo serve` → Play в Studio → кнопка «Играть».
С неба посыпятся буквы, ловим целевую тапом. В логе сервера видно начисление ⭐
и переходы статусов буквы. Озвучки пока нет — будет тишина и предупреждения в логе.

**Дальше (веха 1, см. [12-ROADMAP.md](12-ROADMAP.md)):**
1. Хаб и Башня прогресса вместо временной кнопки «Играть».
2. `ShopService` + `CosmeticsService`, магазин на 12 предметов.
3. Испытания «Эхо-буква» и «Мост слогов» по тому же контракту, что `LetterRain`.
4. Запись первых 60 реплик озвучки и заполнение `AudioRegistry`.
