# 09 — Схемы данных и справочник букв

Всё содержимое игры описано данными. Ни одна буква, слог, слово или предмет
не «зашивается» в код испытаний.

## 1. Справочник букв (единственный источник истины)

`id` — ключ во всех системах: профиле, аудио-реестре, аналитике, ассетах.
Латиница выбрана, чтобы не иметь проблем с кириллицей в именах файлов и ключах DataStore.

| # | Буква | id | Тип | Остров | Звук (озвучка) | Тянется | Слова-примеры |
|--:|:--:|---|---|:--:|---|:--:|---|
| 1 | А | `a` | гласная | 1 | «а-а-а» | ✔ | АИСТ, МАК |
| 2 | У | `u` | гласная | 1 | «у-у-у» | ✔ | УТКА, ЛУНА |
| 3 | О | `o` | гласная | 1 | «о-о-о» | ✔ | ОСЫ, ДОМ |
| 4 | И | `i` | гласная | 1 | «и-и-и» | ✔ | ИВА, КИТ |
| 5 | Ы | `y` | гласная | 1 | «ы-ы-ы» | ✔ | ДЫМ, РЫБА (не в начале!) |
| 6 | Э | `e` | гласная | 1 | «э-э-э» | ✔ | ЭХО, ПОЭТ |
| 7 | М | `m` | согл. звонк. | 2 | «м-м-м» | ✔ | МАМА, ДОМ |
| 8 | П | `p` | согл. глух. | 2 | «п» | ✘ | ПАПА, СУП |
| 9 | Б | `b` | согл. звонк. | 2 | «б» | ✘ | БУСЫ, ЗУБ |
| 10 | Т | `t` | согл. глух. | 3 | «т» | ✘ | ТУТ, КОТ |
| 11 | Д | `d` | согл. звонк. | 3 | «д» | ✘ | ДОМ, ДЫНЯ |
| 12 | Н | `n` | согл. звонк. | 3 | «н-н-н» | ✔ | НОС, ЛУНА |
| 13 | К | `k` | согл. глух. | 4 | «к» | ✘ | КОТ, МАК |
| 14 | Г | `g` | согл. звонк. | 4 | «г» | ✘ | ГУСИ, НОГА |
| 15 | Х | `h` | согл. глух. | 4 | «х-х-х» | ✔ | ХОР, УХО |
| 16 | В | `v` | согл. звонк. | 5 | «в-в-в» | ✔ | ВОДА, СОВА |
| 17 | Ф | `f` | согл. глух. | 5 | «ф-ф-ф» | ✔ | ФОТО, ШКАФ |
| 18 | С | `s` | согл. глух. | 5 | «с-с-с» | ✔ | СОК, ОСА |
| 19 | З | `z` | согл. звонк. | 5 | «з-з-з» | ✔ | ЗИМА, ВАЗА |
| 20 | Л | `l` | согл. звонк. | 6 | «л-л-л» | ✔ | ЛУНА, СТОЛ |
| 21 | Р | `r` | согл. звонк. | 6 | «р-р-р» | ✔ | РУКА, ШАР |
| 22 | Й | `j` | согл. звонк. | 6 | «й» | ✘ | МОЙ, ЧАЙ |
| 23 | Ш | `sh` | шипящая | 7 | «ш-ш-ш» | ✔ | ШАР, МЫШЬ |
| 24 | Ж | `zh` | шипящая | 7 | «ж-ж-ж» | ✔ | ЖУК, НОЖИ |
| 25 | Ч | `ch` | шипящая | 7 | «ч» | ✘ | ЧАС, ЛУЧ |
| 26 | Щ | `shch` | шипящая | 7 | «щ-щ-щ» | ✔ | ЩИ, ПЛАЩ |
| 27 | Ц | `c` | шипящая | 7 | «ц» | ✘ | ЦАПЛЯ, ОГУРЕЦ |
| 28 | Е | `ye` | йотированная | 8 | «йэ» | ✘ | ЕЛЬ, ЛЕС |
| 29 | Ё | `yo` | йотированная | 8 | «йо» | ✘ | ЁЖ, ЁЛКА |
| 30 | Ю | `yu` | йотированная | 8 | «йу» | ✘ | ЮЛА, ЮГ |
| 31 | Я | `ya` | йотированная | 8 | «йа» | ✘ | ЯМА, ЯБЛОКО |
| 32 | Ь | `soft` | знак | 8 | нет звука | — | СОЛЬ, МЫШЬ |
| 33 | Ъ | `hard` | знак | 8 | нет звука | — | ПОДЪЕЗД |

## 2. `Config/Letters.luau`

```lua
--!strict
export type LetterKind = "vowel" | "consonant" | "hissing" | "iotated" | "sign"

export type Letter = {
    id: string,
    glyph: string,          -- "М"
    glyphLower: string,     -- "м"
    kind: LetterKind,
    voiced: boolean?,       -- звонкая/глухая (для согласных)
    sustainable: boolean,   -- можно ли тянуть звук
    island: number,
    order: number,          -- порядок внутри острова
    color: Color3,          -- по типу звука, см. 08-UX-UI
    vo: { sound: string, long: string?, name: string },
    examples: {string},     -- id слов из Words.luau
    confusableWith: {string}, -- пары-путаницы
}

return {
    m = {
        id = "m",
        glyph = "М", glyphLower = "м",
        kind = "consonant", voiced = true, sustainable = true,
        island = 2, order = 1,
        color = Color3.fromRGB(60, 120, 220),
        vo = { sound = "snd_m", long = "snd_long_m", name = "name_m" },
        examples = { "mama", "dom" },
        confusableWith = { "n" },
    },
    -- ... остальные 32
}
```

## 3. `Config/Syllables.luau`

```lua
export type Syllable = {
    id: string,          -- "ma"
    text: string,        -- "МА"
    consonant: string?,  -- "m"
    vowel: string,       -- "a"
    kind: "open" | "closed" | "vv" | "cluster",
    vo: string,          -- "blend_ma" — ОДИН слитный файл, не склейка
    minIsland: number,
}
```

Правила генерации (скрипт, а не ручной ввод):
- открытые слоги: каждая согласная × каждая гласная,
- **исключить**: `zhy`, `shy`, `chy`, `shchy`, `cy` (ЖЫ/ШЫ — не пишем),
  `zhe/she/che` через Э, любые сочетания со знаками,
- закрытые: гласная + согласная, только для «удобных» согласных (М, Н, Т, К, П, С, Х),
- итог ~180 записей, каждая требует своей записи озвучки.

## 4. `Config/Words.luau`

```lua
export type Word = {
    id: string,          -- "kot"
    text: string,        -- "КОТ"
    letters: {string},   -- {"k","o","t"} — порядок для сборки
    syllables: {string}, -- {"ko","t"} — для подсветки при чтении
    vo: string,          -- "word_kot"
    voSyllabic: string,  -- "word_syl_kot"
    image: string,       -- rbxassetid картинки
    model: string?,      -- 3D-модель для оживления
    minIsland: number,   -- когда все буквы доступны
    tags: {string},      -- "animal", "home"
}
```

**Инвариант, проверяемый тестом:** для каждого слова все `letters` должны иметь
`island <= word.minIsland`. Иначе слово попадёт игроку раньше, чем он выучит буквы.

## 5. `Config/Islands.luau`

```lua
export type Island = {
    index: number,
    id: string,               -- "vowels"
    title: string,            -- "Поющий берег"
    letters: {string},
    challenges: {string},     -- id доступных испытаний
    unlockRule: { prevMasteryRatio: number },  -- 0.8
    bossId: string,
    shopSetId: string,        -- какая витрина открывается
    music: string,
    voIntro: string,
}
```

## 6. `Config/Shop.luau`

```lua
export type ShopItem = {
    id: string,                -- "hat_stargazer"
    category: "hat"|"back"|"face"|"trail"|"pet"|"emote"|"tool"|"bundle",
    title: string,
    price: number?,            -- в ⭐; nil = не продаётся за звёздочки
    robuxProduct: number?,     -- productId, если продаётся за Robux
    tier: number,              -- 0..4
    unlockIsland: number,      -- когда появляется в витрине
    assetModel: string,        -- путь к модели в ReplicatedStorage.Cosmetics
    icon: string,
    grantedBy: string?,        -- "letter_mastered:m" — выдаётся автоматически
}
```

**Инварианты:** у предмета должно быть ровно одно из `price` / `robuxProduct` / `grantedBy`.
Один и тот же предмет не может и продаваться, и выдаваться за прогресс.

## 7. `Config/AudioRegistry.luau`

```lua
-- vo_key -> rbxassetid. Единственное место, где живут ID аудио.
return {
    snd_m       = "rbxassetid://0000000001",
    snd_long_m  = "rbxassetid://0000000002",
    blend_ma    = "rbxassetid://0000000003",
    word_kot    = "rbxassetid://0000000004",
    -- ...
}
```

Тест при сборке: каждый `vo`-ключ, упомянутый в Letters/Syllables/Words/Challenges,
обязан существовать в реестре. Отсутствие озвучки = падение сборки, а не тишина в игре.

## 8. `Config/Challenges.luau` (сложность)

```lua
return {
    letter_rain = {
        targetCount    = { 5, 5, 6, 7, 8 },       -- по уровням сложности 1..5
        distractors    = { 1, 2, 3, 4, 4 },
        fallSpeed      = { 6, 8, 10, 12, 14 },
        spawnInterval  = { 1.2, 1.0, 0.9, 0.75, 0.6 },
        hintAfterSec   = { 6, 6, 8, 10, 12 },
    },
    -- ...
}
```

Уровень сложности хранится **на пару (игрок × испытание)** и двигается по правилам из
[02-LEARNING.md § адаптивная сложность](02-LEARNING.md).

## 9. Миграции профиля

```lua
local MIGRATIONS = {
    [1] = function(p) p.settings = p.settings or defaultSettings() end,
    [2] = function(p) p.parent = p.parent or { echoConsent = false } end,
}
```

Правила:
- `version` увеличивается при **любом** изменении структуры;
- миграции применяются последовательно при загрузке;
- поля никогда не удаляются в той же версии, в которой перестали использоваться
  (сначала перестаём писать, через релиз — удаляем).
