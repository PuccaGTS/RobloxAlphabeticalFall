# 07 — Техническая архитектура

## 1. Стек

| Что | Выбор | Почему |
|---|---|---|
| Движок | Roblox / Luau | требование проекта |
| Синхронизация кода | **Rojo** + VS Code | git-первый workflow, нормальный дифф и ревью |
| Типизация | `--!strict` во всех модулях | ловим ошибки до рантайма |
| Сохранения | `DataStoreService` + обёртка (ProfileStore/ProfileService) | защита от гонок и потери данных при телепортах |
| Аналитика | своя таблица событий → внешний сток (при необходимости — `HttpService` в свой бэкенд) | нужны обучающие метрики, встроенной аналитики мало |
| Тесты | TestEZ на чистых модулях (`shared/`) | логика прогрессии обязана быть покрыта |
| Линт | selene + StyLua | единый стиль |

## 2. Структура репозитория

```
AlphabetFall/
├── docs/                     ← эта документация
├── src/
│   ├── shared/               → ReplicatedStorage.Shared
│   │   ├── Config/
│   │   │   ├── Letters.luau          -- 33 буквы, звуки, слова
│   │   │   ├── Syllables.luau        -- ~180 слогов
│   │   │   ├── Words.luau            -- банк слов
│   │   │   ├── Islands.luau          -- состав островов
│   │   │   ├── Shop.luau             -- предметы и цены
│   │   │   ├── Challenges.luau       -- параметры сложности
│   │   │   └── AudioRegistry.luau    -- vo_key → rbxassetid
│   │   ├── Logic/
│   │   │   ├── MasteryRules.luau     -- переходы статусов буквы (чистая функция)
│   │   │   ├── ReviewScheduler.luau  -- интервальное повторение
│   │   │   └── DifficultyCurve.luau  -- адаптивная сложность
│   │   ├── Net/RemoteDefs.luau       -- единый реестр Remote'ов
│   │   └── Types.luau
│   ├── server/               → ServerScriptService.Server
│   │   ├── init.server.luau
│   │   └── Services/
│   │       ├── ProfileService.luau      -- загрузка/сохранение профиля
│   │       ├── ProgressService.luau     -- статусы букв, XP, освоение
│   │       ├── ChallengeService.luau    -- запуск/валидация испытаний
│   │       ├── EconomyService.luau      -- ⭐ начисления и траты
│   │       ├── ShopService.luau         -- покупки, инвентарь
│   │       ├── CosmeticsService.luau    -- надевание аксессуаров, питомцы
│   │       ├── MonetizationService.luau -- Game Passes, Dev Products
│   │       ├── AnalyticsService.luau
│   │       └── ParentService.luau
│   └── client/               → StarterPlayerScripts.Client
│       ├── init.client.luau
│       ├── Controllers/
│       │   ├── AudioController.luau     -- очередь VO, дакинг музыки
│       │   ├── ChallengeController.luau -- презентация испытаний
│       │   ├── EchoController.luau      -- режимы A/B/C микрофона
│       │   ├── UIController.luau
│       │   ├── CameraController.luau
│       │   └── TutorialController.luau
│       └── UI/                          -- компоненты интерфейса
├── assets/                   -- исходники (не в Roblox): аудио WAV, спрайты
│   └── audio/vo/
├── tests/
├── default.project.json      -- Rojo
├── selene.toml
└── stylua.toml
```

## 3. Архитектурные принципы

1. **Сервер — источник истины.** Клиент не решает, засчитан ли ответ, сколько ⭐ начислить
   и открыт ли остров. Клиент только показывает и отправляет намерения.
2. **Конфиг отделён от логики.** Все числа (цены, скорости, пороги) — в `shared/Config`.
   Ни одного «магического числа» в сервисах.
3. **Чистая логика тестируема.** `MasteryRules`, `ReviewScheduler`, `DifficultyCurve` —
   чистые функции без обращения к Roblox API, покрыты юнит-тестами.
4. **Один Remote — одно намерение.** Никаких универсальных `DoAction(payload)`.
5. **Каждое испытание — модуль по общему контракту** (см. §5), новые добавляются
   без правки ядра.

## 4. Данные игрока

### Профиль (сохраняется)

```lua
type LetterProgress = {
    mastery: number,      -- 0 незнакомая, 1 знакомая, 2 изученная, 3 освоенная
    correct: number,
    wrong: number,
    lastSeen: number,     -- os.time()
    nextReview: number,   -- os.time(), планировщик
    streak: number,
    types: {string},      -- в каких типах испытаний был успех
    avgReactionMs: number,
}

type Profile = {
    version: number,               -- для миграций!
    stars: number,
    level: number,
    xp: number,
    letters: {[string]: LetterProgress},   -- ключ = letterId ("m", "a", ...)
    syllables: {[string]: boolean},
    words: {[string]: boolean},
    islands: {[number]: {unlocked: boolean, bossDone: boolean, chests: {string}}},
    inventory: {string},           -- id предметов
    equipped: {hat: string?, back: string?, face: string?, trail: string?, pets: {string}},
    dailyStreak: number,
    lastLoginDay: number,
    settings: {music: number, sfx: number, echoMode: string, subtitles: boolean},
    parent: {pinHash: string?, dailyLimitMin: number?, echoConsent: boolean},
    stats: {totalPlayMin: number, sessionsCount: number, firstJoin: number},
}
```

### Правила работы с DataStore

- Обёртка с session-lock (ProfileStore/ProfileService) — **обязательна**, иначе при
  двойном входе профиль затирается.
- Автосохранение раз в 60 с + на `PlayerRemoving` + на `BindToClose`.
- **Поле `version` и функции миграции** — с первого дня. Схема будет меняться,
  а профили детей терять нельзя.
- Профиль никогда не отправляется клиенту целиком — только нужные срезы
  (звёзды, инвентарь, прогресс текущего острова).

## 5. Контракт испытания

Каждое испытание реализует один интерфейс — это позволяет добавлять новые
мини-игры без изменения ядра:

```lua
export type ChallengeModule = {
    id: string,
    trains: {string},          -- {"recognize", "sound_to_letter", ...}
    minLetters: number,

    -- сервер строит задание из очереди повторений
    Build: (player: Player, letters: {string}, difficulty: number) -> ChallengeSpec,

    -- сервер валидирует каждое действие клиента
    Validate: (state: ChallengeState, action: ClientAction) -> ValidationResult,

    -- итог: что записать в прогресс
    Finish: (state: ChallengeState) -> ChallengeResult,
}
```

`ChallengeResult` содержит `{letterId, correct, reactionMs, hintsUsed}` по каждой попытке —
именно эти события кормят `ProgressService`, `ReviewScheduler` и аналитику.

## 6. Сеть (RemoteDefs)

| Remote | Направление | Назначение |
|---|---|---|
| `ProfileSnapshot` | S→C | срез профиля при входе и после изменений |
| `StartChallenge` | C→S | запрос старта (id испытания) |
| `ChallengeSpec` | S→C | задание: буквы, раскладка, seed |
| `ChallengeAction` | C→S | «тапнул объект #7 в t=1234мс» |
| `ChallengeFeedback` | S→C | верно/неверно + какую реплику проиграть |
| `ChallengeEnd` | S→C | итог, звёзды, награда |
| `BuyItem` | C→S | покупка (id предмета) |
| `EquipItem` | C→S | надеть/снять |
| `PlayVO` | S→C | попросить клиент проиграть реплику по vo_key |
| `EchoReport` | C→S | факт «сказал» (режим A/B), без аудиоданных |
| `ParentAuth` | C→S | вход в родительский режим (PIN) |

**Rate limiting на каждом Remote** (например, `ChallengeAction` ≤ 20/с) —
защита от спама и от лагов клиента.

## 7. Безопасность

- ⭐ начисляются **только** внутри `EconomyService` по результату `Finish()` серверного
  испытания. Клиентского пути начисления не существует.
- Цена берётся из серверного конфига; запрос клиента содержит только `itemId`.
- Позиции объектов испытания генерируются на сервере по `seed`; клиент их только рисует.
- Валидация времени реакции: ответ быстрее 120 мс после появления цели → помечается
  подозрительным (не наказываем ребёнка, но не засчитываем в статистику освоения).
- Все Remote-хендлеры проверяют тип и диапазон аргументов (`typeof`, whitelist id).
- Любой текст, который может увидеть другой игрок (если появится) — через
  `TextService:FilterStringAsync`. Сейчас такого текста нет по дизайну.

## 8. Производительность (важно для дешёвых Android-планшетов)

Целевое устройство — планшет 4 ГБ RAM. Бюджеты:

- **30 FPS минимум** на целевом устройстве, 60 — на ПК.
- Не более **~800 частей** в зоне видимости; острова разделены на стриминг-зоны
  (`StreamingEnabled = true`).
- Буквы — **MeshPart** с общим `SurfaceAppearance`, не Union и не CSG в рантайме.
- Максимум 2 динамических источника света на кадр, тени — только от персонажа.
- UI — переиспользование пула элементов, никаких пересозданий `Frame` каждый кадр.
- Аудио: предзагрузка островной пачки VO, выгрузка при смене острова.
- Никакой физики у питомцев/букв: `AlignPosition` + `Anchored`, движение через
  `TweenService`/`RunService` без коллизий.

## 9. Логирование и аналитика

События (минимум для обучающих метрик):

```
session_start / session_end (длительность)
challenge_start (id, island, difficulty)
letter_answer (letterId, challengeId, correct, reactionMs, hintsUsed)
mastery_change (letterId, from, to)
syllable_first_read (syllableId)
word_first_built (wordId)
economy_earn / economy_spend (source, amount, balance)
shop_purchase (itemId, price)
echo_mode (mode A/B/C)
parent_open / parent_setting_change
error_client / error_server
```

Все события — с `userId` (внутренним, не персональным), `timestamp`, `sessionId`.
Персональные данные, голос, тексты — **не логируются никогда**.

## 10. Окружения

- **dev** — отдельный опыт, тестовые DataStore-ключи, отладочные команды, скип обучения.
- **staging** — приватный опыт для теста на реальных детях (с согласия родителей).
- **prod** — публичный. Флаги фич через `MemoryStoreService`/конфиг, чтобы гасить
  проблемное испытание без перевыпуска.

## 11. Порядок работ по коду (после утверждения доков)

1. Rojo-скелет, `Types`, `Config/Letters` на 9 букв, пустые сервисы.
2. `ProfileService` + сохранение/загрузка + миграции.
3. `AudioController` с очередью и дакингом (без него ничего не проверить на слух).
4. Испытание «Буквопад» целиком по контракту §5.
5. `ProgressService` + `MasteryRules` + юнит-тесты.
6. `EconomyService` + магазин из 6 предметов + `CosmeticsService`.
7. «Эхо-буква» (режим A) и «Мост слогов».
8. Хаб, Башня, туториал первых 10 минут.
