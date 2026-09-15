--!strict
--[[
	Общие типы проекта. Единственное место, где живут структуры данных.
	См. docs/09-DATA-SCHEMA.md
]]

local Types = {}

-- ===== Буквы =====================================================================

--[[
	Вид буквы. Нужен для цвета (docs/08-UX-UI.md) и для подсказок родителю —
	не для обучения звукам: звуки игра не даёт вовсе, см. docs/02-LEARNING.md § 1.
]]
export type LetterKind = "vowel" | "consonant" | "hissing" | "sign"

export type LetterVO = {
	--[[
		Название буквы: «Буква М», «Мягкий знак». Ровно одна реплика на букву,
		и другой озвучки у буквы нет.

		Раньше здесь жили ещё три ключа — изолированный звук, растянутый звук
		и реплика знакомства. Все они требовали записи чистых звуков («м-м-м»),
		а именно она и не получилась: обработка голоса съедала взрывные согласные,
		и П, Б, Т на слух переставали различаться. Название буквы — обычная речь,
		она записывается и обрабатывается без потерь.
	]]
	name: string, -- "letter_m"
}

export type Letter = {
	id: string, -- ключ во всех системах: "m"
	glyph: string, -- "М"
	glyphLower: string, -- "м"
	kind: LetterKind,
	order: number, -- 1..33, место в алфавите. Оно же порядок изучения
	stage: number, -- 1..11, ступень из Config/Stages
	color: Color3,
	vo: LetterVO,
	--[[
		Слово-иллюстрация для карточки буквы и для совета родителю: «АРБУЗ».
		Просто текст, без озвучки: слова игра не читает и читать не учит.
	]]
	example: string,
	confusableWith: { string }, -- похожие по НАЧЕРТАНИЮ, см. docs/02-LEARNING.md § 6
}

-- ===== Ступени алфавита ==========================================================

export type Stage = {
	index: number, -- 1..11
	id: string,
	title: string, -- «Первые три»
	glyphs: string, -- «А Б В» — как ступень подписана в мире
	letters: { string },
	challenges: { string },
	unlockPrevMasteryRatio: number, -- 0.8 = 80% букв предыдущей ступени
	music: string,
}

-- ===== Математика ================================================================

--[[
	Виды задач. В docs/16-MATH.md § 4 перечислены шесть, но таблица ступеней в § 2
	содержит ещё «равные группы» и «умножение» (ступени 10 и 11) — они добавлены сюда.
]]
export type MathKind = "count" | "digit" | "compare" | "add" | "sub" | "compose" | "group" | "mul"

export type MathStage = {
	stage: number, -- 1..11, порядок изучения
	id: string, -- "count_group"
	title: string,
	kind: MathKind,
	min: number, -- границы чисел ступени
	max: number,
	showPips: boolean, -- показывать точки под цифрой: сначала количество, потом значок
	objects: string?, -- что считаем: "berry", "apple"
	choices: number, -- сколько проёмов в воротах по умолчанию
}

export type MathTask = {
	id: string,
	stage: number,
	kind: MathKind,
	prompt: string, -- "2 + 2" либо "" для устных заданий
	--[[
		Озвучка задания — цепочка коротких кусков, а не один файл:
		«Сколько будет» + «два» + «плюс» + «два». Почему так — Config/Math, шапка.
	]]
	vo: { string },
	answer: number,
	answers: { number }, -- варианты для проёмов, включая верный
	objects: string?,
	showPips: boolean,
	-- Равные группы и умножение: сколько тарелок и по сколько на каждой.
	-- По ним рисуются предметы над воротами — ребёнок считает их, а не читает число.
	groups: number?,
	each: number?,
}

-- ===== Препятствия ===============================================================

-- Что ребёнок делает с элементом полосы: перепрыгнуть, обойти, пройти по узкому.
export type ObstacleKind =
	"barrier"
	| "gap"
	| "arch"
	| "beam"
	| "steps"
	| "pendulum"
	| "platform"
	| "fading"
	| "trampoline"
	| "ice"
	| "stones"
	| "roller"
	| "pistons"
	| "comb"

export type Obstacle = {
	id: string,
	kind: ObstacleKind,
	title: string,
	tier: number, -- 1 базовый, 2 средний, 3 сложный, см. docs/19-OBSTACLES.md
	lanes: number, -- сколько дорожек из трёх занимает элемент
	blocking: boolean, -- перекрывает ли дорожку насмерть (обойти обязательно)
	-- Элемент живёт сам: качается, ездит, гаснет. Таких на отрезке не больше двух,
	-- иначе отрезок превращается в аттракцион на реакцию (docs/19-OBSTACLES.md § 3.3).
	moving: boolean,
	-- Встаёт только в крайнюю дорожку: поршень выезжает из стены, и в средней
	-- дорожке ему неоткуда выехать, не перегородив соседнюю.
	edge: boolean?,
}

-- ===== Прогресс игрока ===========================================================

-- 0 незнакомая · 1 знакомая · 2 изученная · 3 освоенная
export type Mastery = number

--[[
	Прогресс по одной изучаемой единице. Единица — буква или ступень математики:
	правила освоения у них общие (Logic/MasteryRules и Logic/ReviewScheduler
	не знают, что именно осваивается, и знать не должны — docs/16-MATH.md § 4).
]]
export type TopicProgress = {
	mastery: Mastery,
	correct: number,
	wrong: number,
	streak: number,
	types: { string }, -- в каких типах испытаний был успех
	lastSeen: number, -- os.time()
	learnedAt: number?, -- когда достигнут статус 2 (нужно для правила «через 2 дня»)
	masteredAt: number?, -- когда достигнут статус 3
	reviewStep: number, -- индекс интервала повторения, см. Logic/ReviewScheduler
	nextReview: number, -- os.time()
	avgReactionMs: number,
	answers: number, -- сколько всего ответов учтено в avgReactionMs
}

-- Прогресс по букве — частный случай прогресса по теме, и никаких своих полей у него нет.
export type LetterProgress = TopicProgress

--[[
	Один ответ ребёнка. letterId — что именно осваивалось: id буквы либо id ступени
	математики («add», «compose»). Поле называется так по истории, а не по смыслу:
	переименовывать его в профилях детей дороже, чем объяснить здесь.
]]
export type Answer = {
	letterId: string,
	challengeId: string,
	correct: boolean,
	reactionMs: number,
	hintsUsed: number,
}

-- ===== Профиль ===================================================================

export type Equipped = {
	hat: string?,
	back: string?,
	face: string?,
	trail: string?,
	petskin: string?, -- скин всех буквят сразу: предмет Config/Shop категории "petskin"
	pets: { string },
}

export type Settings = {
	music: number,
	sfx: number,
	voice: number,
	subtitles: boolean,
	slowSpeech: boolean,
	hideRobux: boolean,
}

export type ParentData = {
	pinHash: string?,
	dailyLimitMin: number?, -- nil — лимита нет; иначе 15 / 20 / 30 / 45, см. Logic/PlayLimit
	restReminder: boolean, -- напоминать об отдыхе раз в 20 минут
}

export type StageProgress = {
	unlocked: boolean,
	chests: { string },
}

--[[
	Незаконченный забег: где ребёнок остановился и из чего этот забег собрать заново.

	Хранится не геометрия, а рецепт: сид, очередь букв и сложность. По ним план
	забега воспроизводится байт в байт, поэтому вернувшийся ребёнок попадает
	в тот же самый туннель, а не в новый, случайно похожий.

	checkpoint — индекс последней пройденной арки-сохранки. Ноль означает, что
	ребёнок начал забег, но ни одной сохранки не достиг: тогда забег начнётся сначала.

	Ключ в Profile.runs — идентификатор испытания. У мира букв забег один —
	«Азбучный туннель» за порталом, — и незаконченный уровень у ребёнка тоже
	всегда один, поэтому уровень лежит полем рецепта, а не ключом.
]]
export type SavedRun = {
	challengeId: string,
	seed: number,
	letters: { string },
	difficulty: number,
	checkpoint: number,
	savedAt: number, -- os.time()
	--[[
		Ступень математики, если забег был математическим. Она часть рецепта наравне
		с сидом: за ночь ребёнок мог открыть следующую ступень, и без этого поля
		он вернулся бы в туннель, похожий на свой, но с другими задачами.
	]]
	stage: number?,
	-- Уровень мира букв (Config/Levels): от него зависят буквы на отрезках.
	level: number?,
}

--[[
	Сутки занятий: номер дня по Logic/PlayLog.dayOf и сколько секунд в тот день
	ребёнок провёл в игре. Два числа, а не дата строкой: сравнивать дни — вычитанием.
]]
export type PlayDay = {
	day: number,
	sec: number,
}

--[[
	Буква дня и серия дней, см. Logic/DailyLetter. Серия здесь своя, а не dailyStreak:
	та считает дни, когда ребёнок просто играл, для отчёта родителя, а эта —
	дни, когда он прошёл букву дня, и она не сгорает при пропуске.
]]
export type DailyLetter = {
	day: number, -- на какие сутки выбрана буква (PlayLog.dayOf)
	letterId: string?,
	done: number, -- сколько заданий из трёх сделано сегодня
	streak: number,
	best: number, -- рекорд серии: награда за серию только за новый рекорд
	lastDay: number, -- последний день, когда буква дня пройдена целиком
}

export type Profile = {
	version: number,
	stars: number,
	level: number,
	xp: number,
	letters: { [string]: LetterProgress },
	--[[
		Прогресс по математике: ключ — id ступени из Config/Math («digit_small»),
		значение — тот же прогресс, что у буквы. Открытость ступени тут не хранится,
		она считается из статусов (Math.isUnlocked): две записи об одном и том же
		рано или поздно разошлись бы.

		Математика и буквы никогда не блокируют друг друга (docs/16-MATH.md § 6),
		поэтому это отдельное поле, а не общая таблица.
	]]
	math: { [string]: TopicProgress },
	stages: { [number]: StageProgress },
	runs: { [string]: SavedRun }, -- незаконченные забеги, см. SavedRun
	--[[
		Сколько уровней пройдено подряд в каждом мире: ключ — мир («letters»),
		значение — номер последнего пройденного. Одно число, а не список:
		уровни открываются строго по очереди, и пропусков в пути не бывает.
	]]
	levels: { [string]: number },
	-- Сделанные шаги обучения первых минут, см. Logic/Tutorial. Пустая таблица — новичок.
	tutorial: { [string]: boolean },
	-- Участок на спавне: уровень каждой категории построек, см. Config/Base.
	-- Несколько чисел, а не список объектов: дёшево сохранять и нечему ломаться.
	base: { [string]: number },
	inventory: { string },
	equipped: Equipped,
	difficulty: { [string]: number }, -- уровень сложности на каждое испытание
	dailyStreak: number,
	-- Последний день, засчитанный в серию (PlayLog.dayOf), а не день входа:
	-- имя осталось с тех пор, когда поле никто не писал.
	lastLoginDay: number,
	playLog: { PlayDay }, -- посуточная история занятий, см. Logic/PlayLog
	daily: DailyLetter,
	settings: Settings,
	parent: ParentData,
	stats: {
		totalPlayMin: number,
		sessionsCount: number,
		firstJoin: number,
	},
}

-- ===== Испытания =================================================================

export type ChallengeSpec = {
	challengeId: string,
	seed: number,
	letters: { string },
	difficulty: number,
	stage: number?, -- ступень счёта, если забег математический
	level: number?, -- уровень мира букв, если забег идёт по уровням
	targetCount: number,
	params: { [string]: any },
}

export type ChallengeResult = {
	challengeId: string,
	stars: number, -- 1..3
	answers: { Answer },
	rewardStars: number,
}

return Types
