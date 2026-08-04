# RobloxAlphabeticalFall

Обучающая игра для Roblox: дети 4–7 лет учат русские буквы и счёт.
Ребёнок бежит по туннелю, на воротах выбирает нужную букву или ответ на пример,
собирает Звёздочки и строит на них свой дом.

**Стадия:** ранняя разработка. Играбельное ядро есть, озвучки и арта пока нет.

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
| Линтер | `selene src tests tools` |

---

## Структура

```
src/shared    конфиги, чистая логика, типы, реестр Remote'ов
src/server    источник истины: прогресс, экономика, испытания, мир
src/client    презентация: звук, интерфейс, ввод
tests         юнит-тесты
docs          документация проекта
```

---

## Что делать дальше

Все задачи с галочками — в [CHECKLIST.md](CHECKLIST.md).

Ближайшее: записать озвучку по списку [docs/VO-SCRIPT.md](docs/VO-SCRIPT.md).
Половина написанных механик без звука работает вхолостую.

---

## Документация

| Файл | О чём |
|---|---|
| [00-VISION](docs/00-VISION.md) | Зачем игра и для кого |
| [01-GDD](docs/01-GDD.md) | Игровой цикл и прогрессия |
| [02-LEARNING](docs/02-LEARNING.md) | Методика: порядок букв, слоги, повторения |
| [03-CHALLENGES](docs/03-CHALLENGES.md) | Испытания |
| [04-ECONOMY](docs/04-ECONOMY.md) | Валюта, магазин, монетизация |
| [05-AUDIO-VO](docs/05-AUDIO-VO.md) | Требования к озвучке |
| [06-MICROPHONE](docs/06-MICROPHONE.md) | Что реально можно с микрофоном в Roblox |
| [07-TECH-ARCH](docs/07-TECH-ARCH.md) | Архитектура и защита от читов |
| [08-UX-UI](docs/08-UX-UI.md) | Интерфейс для нечитающего ребёнка |
| [09-DATA-SCHEMA](docs/09-DATA-SCHEMA.md) | Схемы данных и справочник букв |
| [10-CONTENT-PIPELINE](docs/10-CONTENT-PIPELINE.md) | Ассеты: форматы, именование, загрузка |
| [11-COMPLIANCE](docs/11-COMPLIANCE.md) | Правила Roblox, приватность, безопасность детей |
| [12-ROADMAP](docs/12-ROADMAP.md) | Вехи |
| [13-PARENT-MODE](docs/13-PARENT-MODE.md) | Родительский режим |
| [14-TUNNEL-MODE](docs/14-TUNNEL-MODE.md) | Основной режим: туннель и сохранки |
| [15-HOME-BASE](docs/15-HOME-BASE.md) | Дом игрока |
| [16-MATH](docs/16-MATH.md) | Счёт и примеры |
| [17-CONTENT-PLAN](docs/17-CONTENT-PLAN.md) | Сколько всего строить |
| [18-CONTENT-BACKLOG](docs/18-CONTENT-BACKLOG.md) | Бэклог идей с приоритетами |
| [20-VO-SESSION-1](docs/20-VO-SESSION-1.md) | Как записывать озвучку |
| [VO-SCRIPT](docs/VO-SCRIPT.md) | Список реплик для записи |
| [HOW-TO-CHECK](docs/HOW-TO-CHECK.md) | Сценарий проверки игры |
| [DEV-SETUP](docs/DEV-SETUP.md) | Подробная настройка окружения |
