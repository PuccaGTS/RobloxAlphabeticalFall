# RobloxAlphabeticalFall

Обучающая игра для Roblox: дети 4–7 лет учат русский алфавит и счёт.
Голос называет букву — ребёнок ищет её: ловит в буквопаде, выбирает в воротах на бегу,
поднимается по алфавитной лестнице, спасается от лавы на нужной букве.
Между заданиями — паркур: островки, валуны, молоты.
За обучение капают Звёздочки, на них строится свой дом.

**Стадия:** ранняя разработка. Играбельное ядро есть, озвучки и арта пока нет.

> **Игра учит алфавиту, а не чтению.** Узнать букву, назвать её, знать порядок —
> да. Звуки, слоги и слова — нет: озвучку изолированных звуков записать не удалось,
> и концепция сменилась. Разбор — [docs/02-LEARNING.md](docs/02-LEARNING.md) § 1
> и [docs/05-AUDIO-VO.md](docs/05-AUDIO-VO.md) § 1.

---

## Как начать разрабатывать

### 1. Установить Roblox Studio

```
winget install --id Roblox.RobloxStudio
```

Если winget ругается на хеш — скачать напрямую с https://create.roblox.com
Запустить один раз и войти в аккаунт Roblox.

### 2. Установить инструменты

```
winget install --id Rojo.Rokit
```

Затем в папке проекта:

```
rokit install
```

Поставит Rojo, Wally, StyLua, selene и run-in-roblox нужных версий.
**Перезапустить консоль**, чтобы подхватился PATH.

### 3. Поставить зависимости

```
wally install
```

Нужно только для тестов.

### 4. Поставить плагин Rojo в Studio

Скачать `Rojo.rbxm` со страницы релизов https://github.com/rojo-rbx/rojo/releases
и положить в `%LOCALAPPDATA%\Roblox\Plugins`, затем перезапустить Studio.

### 5. Запустить

```
rojo serve
```

В Studio: **New → Baseplate** → вкладка **Plugins** → **Rojo** → **Connect** → **Play**.

Логи смотреть в **View → Output** — они появляются только в режиме Play.

---

## Команды

| Что | Команда |
|---|---|
| Синхронизация со Studio | `rojo serve` |
| Собрать место | `rojo build -o build/game.rbxl` |
| Собрать тесты | `rojo build test.project.json -o build/test.rbxl` |
| Прогнать тесты | `run-in-roblox --place build/test.rbxl --script tools/TestRunner.server.luau` |
| Формат кода | `stylua src tests tools` |
| Проверка в настоящем Play | `python tools/playtest/run.py walk` — Studio сама открывает место, персонаж ходит к падам и порталам, отчёт в консоль |
| Иконка и превью страницы игры | `ZZ_WINDOW=2300x1320 python tools/playtest/run.py store`, затем `python tools/store/make.py` |
| Снимок сцены в PNG | `python tools/render/run.py tools/render/PlotCheck.server.luau build/render` |
| Линтер | `selene src tests tools` |
| Проверить озвучку | `python tools/audio/prepare_vo.py --check` |

---

## Структура

```
src/shared    конфиги, чистая логика, типы, реестр Remote'ов
src/server    источник истины: прогресс, экономика, испытания, мир
src/client    презентация: звук, интерфейс, ввод
assets/models модели для мира: сюда кладётся арт (docs/21-DECOR.md)
assets/audio  манифест озвучки и музыки
tests         юнит-тесты
docs          документация проекта
```

---

## Что делать дальше

Все задачи с галочками — в [CHECKLIST.md](CHECKLIST.md).

**Ближайшее и самое важное: записать 43 реплики по листу
[docs/VO-RECORD.md](docs/VO-RECORD.md)** — 33 названия букв и 10 чисел. Озвучка
минимальная ([docs/05-AUDIO-VO.md](docs/05-AUDIO-VO.md) § 0): в Roblox дети обычно
играют без звука, поэтому задания, похвала и сюжет — подписи на экране, а голосом
звучат только буквы и числа — то, что надо услышать.

Модели декораций можно приносить параллельно и по одной — как именно,
написано в [docs/21-DECOR.md](docs/21-DECOR.md). Пока модели нет, на её месте
стоит заглушка того же размера, и мир не выглядит пустым.

---

## Документация

| Файл | О чём |
|---|---|
| [00-VISION](docs/00-VISION.md) | Зачем игра и для кого |
| [01-GDD](docs/01-GDD.md) | Игровой цикл и прогрессия |
| [02-LEARNING](docs/02-LEARNING.md) | Методика: чему учим, порядок букв, повторения |
| [03-CHALLENGES](docs/03-CHALLENGES.md) | Испытания |
| [04-ECONOMY](docs/04-ECONOMY.md) | Валюта, магазин, монетизация |
| [05-AUDIO-VO](docs/05-AUDIO-VO.md) | Озвучка: что записываем и почему именно так |
| [06-MICROPHONE](docs/06-MICROPHONE.md) | Почему микрофон не используется |
| [07-TECH-ARCH](docs/07-TECH-ARCH.md) | Архитектура и защита от читов |
| [08-UX-UI](docs/08-UX-UI.md) | Интерфейс для нечитающего ребёнка |
| [09-DATA-SCHEMA](docs/09-DATA-SCHEMA.md) | Схемы данных и справочник букв |
| [10-CONTENT-PIPELINE](docs/10-CONTENT-PIPELINE.md) | Ассеты: форматы, именование, загрузка |
| [11-COMPLIANCE](docs/11-COMPLIANCE.md) | Правила Roblox, приватность, безопасность детей |
| [12-ROADMAP](docs/12-ROADMAP.md) | Вехи |
| [13-PARENT-MODE](docs/13-PARENT-MODE.md) | Родительский режим |
| [14-TUNNEL-MODE](docs/14-TUNNEL-MODE.md) | Основной режим: забег и сохранки |
| [15-HOME-BASE](docs/15-HOME-BASE.md) | Дом игрока |
| [16-MATH](docs/16-MATH.md) | Счёт и примеры |
| [17-CONTENT-PLAN](docs/17-CONTENT-PLAN.md) | Сколько всего строить |
| [18-CONTENT-BACKLOG](docs/18-CONTENT-BACKLOG.md) | Бэклог идей с приоритетами |
| [19-OBSTACLES](docs/19-OBSTACLES.md) | Препятствия и аттракционы забега |
| [20-VO-SESSION-1](docs/20-VO-SESSION-1.md) | Как записывать озвучку |
| [21-DECOR](docs/21-DECOR.md) | Как добавлять модели и декор |
| [VO-RECORD](docs/VO-RECORD.md) | Лист записи: 43 реплики |
| [VO-SCRIPT](docs/VO-SCRIPT.md) | Справочник реплик и подписей |
| [HOW-TO-CHECK](docs/HOW-TO-CHECK.md) | Сценарий проверки игры |
| [DEV-SETUP](docs/DEV-SETUP.md) | Подробная настройка окружения |
