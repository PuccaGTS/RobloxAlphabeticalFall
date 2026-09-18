--!strict
--[[
	Параметры испытаний по уровням сложности 1..5.
	Ни одного «магического числа» в коде испытаний — только отсюда.
	См. docs/03-CHALLENGES.md и docs/09-DATA-SCHEMA.md § 8.

	Чему вообще учат испытания (поле trains):
	  recognize — узнать букву, когда её назвали вслух;
	  name      — вспомнить название буквы, увидев её;
	  order     — знать, какая буква идёт следующей в алфавите;
	  shape     — отличить букву от похожей по начертанию.

	Испытаний на звук, слог и чтение слова здесь больше нет — игра учит алфавит,
	см. docs/02-LEARNING.md § 1.
]]

export type ChallengeMeta = {
	id: string,
	title: string,
	voInstruction: string,
	trains: { string },
	minLetters: number,
	maxSeconds: number,
	params: { [string]: { number } },
}

local Challenges: { [string]: ChallengeMeta } = {
	letter_rain = {
		id = "letter_rain",
		title = "Буквопад",
		voInstruction = "instr_letter_rain",
		trains = { "recognize" },
		minLetters = 2,
		maxSeconds = 120,
		params = {
			targetCount = { 5, 5, 6, 7, 8 },
			distractors = { 1, 2, 3, 4, 4 },
			--[[
				Буквы ловят бегом, а не щелчком: падают медленнее и реже, чем
				падали на экран, — до буквы надо успеть добежать по полю.
			]]
			fallSpeed = { 5, 6, 7, 8, 9 }, -- studs/sec
			spawnInterval = { 1.8, 1.6, 1.4, 1.2, 1.1 }, -- sec
			restTime = { 3, 2.6, 2.3, 2, 1.8 }, -- sec: сколько буква лежит на траве
			hintAfterSec = { 6, 6, 8, 10, 12 },
			-- Пауза после промаха: «сачок опустился». Не наказание, а плата временем —
			-- за неё ребёнок слышит тронутую букву и снова цель. Без неё задание
			-- решается перебором, и слушать становится незачем.
			missCooldown = { 1.4, 1.2, 1.1, 1.0, 0.9 },
		},
	},

	--[[
		«Алфавитная лестница» заняла место, на котором раньше стоял «Мост слогов»:
		тот же ритм (одна ступень за раз, выбор из нескольких плит), но учит она
		не слиянию звуков, а порядку букв. Это единственное испытание, которое
		спрашивает «что дальше», а не «где эта».
	]]
	alphabet_ladder = {
		id = "alphabet_ladder",
		title = "Алфавитная лестница",
		voInstruction = "instr_alphabet_ladder",
		trains = { "order", "name" },
		minLetters = 2,
		maxSeconds = 150,
		params = {
			rungs = { 5, 6, 6, 7, 8 }, -- сколько ступеней в лестнице; меньше пяти не бывает
			choices = { 2, 3, 3, 4, 4 }, -- из скольких плит выбирать
			hintAfterSec = { 8, 8, 10, 12, 12 },
			missCooldown = { 1.6, 1.4, 1.2, 1.1, 1.0 },
		},
	},

	--[[
		Туннель и полоса препятствий — единственные испытания, чьи параметры живут
		не здесь, а в Config/Tunnel: там геометрия, дорожки и расстояния,
		и разрывать их надвое бессмысленно.
	]]
	tunnel_run = {
		id = "tunnel_run",
		title = "Азбучный туннель",
		voInstruction = "instr_tunnel_run",
		trains = { "recognize" },
		minLetters = 2,
		maxSeconds = 600,
		params = {},
	},

	--[[
		«Пол — это лава!» (docs/03-CHALLENGES.md § 9): арена из плит с буквами,
		через несколько секунд весь пол, кроме плит с названной буквой, становится
		лавой. Встал на свою — звёздочка, не успел — лава подбрасывает, и дальше
		следующий раунд. Заняла пад «Полосы препятствий»: та была тем же забегом,
		что и портал, и разницы между ними на живой проверке не увидели.
	]]
	lava_floor = {
		id = "lava_floor",
		title = "Пол — это лава!",
		voInstruction = "instr_lava_floor",
		trains = { "recognize" },
		minLetters = 2,
		maxSeconds = 150,
		params = {
			rounds = { 5, 5, 6, 7, 8 },
			seconds = { 8, 7, 6.5, 6, 5.5 }, -- на поиск своей плиты
			targets = { 6, 5, 5, 4, 4 }, -- своих плит в первом раунде; дальше меньше
			kinds = { 1, 2, 2, 3, 3 }, -- сколько разных чужих букв на полу
		},
	},

	--[[
		«Ворота с числами» — вход в мир математики. Устройство то же, что у туннеля
		с буквами: коридор, стена с проёмами, над каждым ответ. Отличие одно, и оно
		принципиальное: задача меняется у КАЖДЫХ ворот, потому что счёт тренируется
		повторением разных примеров, а не одним числом на весь забег
		(docs/16-MATH.md § 3.1).

		Параметры, как и у забегов с буквами, живут в Config/Tunnel — там геометрия.
	]]
	math_gates = {
		id = "math_gates",
		title = "Ворота с числами",
		voInstruction = "instr_math_gates",
		trains = { "count" },
		minLetters = 0, -- буквы этому испытанию не нужны вовсе
		maxSeconds = 600,
		params = {},
	},

	--[[
		«Пузыри» — самое спокойное занятие: пузыри с буквами медленно всплывают
		и уходят вниз по кругу, пока их не лопнут, так что успеть можно всё.
		Лопнул не тот — пузырь превращается в рыбку и уплывает: не наказание,
		а «мимо» (docs/03-CHALLENGES.md § 5). В отвлекающие первыми идут похожие
		по начертанию буквы: здесь их удобнее всего различать без спешки.
	]]
	bubbles = {
		id = "bubbles",
		title = "Пузыри",
		voInstruction = "instr_bubbles",
		trains = { "recognize" },
		minLetters = 2,
		maxSeconds = 100,
		params = {
			targetCount = { 3, 3, 4, 4, 5 },
			totalBubbles = { 8, 10, 12, 14, 16 },
			riseSpeed = { 2, 2.5, 3, 3.5, 4 },
			hintAfterSec = { 7, 7, 9, 10, 12 },
			missCooldown = { 1.2, 1.1, 1, 0.9, 0.8 },
		},
	},

	--[[
		«Зеркало» лечит классическую дошкольную беду — зеркальное написание
		(Я, Р, З, Э, Ю). Пока звуки были главными, оно было второстепенным;
		теперь, когда буква узнаётся глазами и по названию, оно стало по делу.
	]]
	mirror = {
		id = "mirror",
		title = "Зеркало",
		voInstruction = "instr_mirror",
		trains = { "shape", "recognize" },
		minLetters = 1,
		maxSeconds = 100,
		params = {
			rounds = { 4, 5, 5, 6, 6 },
			variants = { 2, 3, 3, 4, 4 }, -- сколько вариантов написания показываем
			hintAfterSec = { 8, 8, 10, 10, 12 },
			missCooldown = { 1.4, 1.2, 1.1, 1, 1 },
		},
	},

	--[[
		«Весы» — равенство количеств: на левой чаше камни, выбрать кучку, которая
		уравновесит (docs/16-MATH.md § 3.3). Второе испытание мира математики
		и единственное, где счёт идёт сравнением, а не выбором числа.
		Камней не больше, чем позволяет ступень счёта ребёнка (Challenges/Scales).
	]]
	scales = {
		id = "scales",
		title = "Весы",
		voInstruction = "instr_scales",
		trains = { "count" },
		minLetters = 0,
		maxSeconds = 120,
		params = {
			rounds = { 3, 4, 4, 5, 5 },
			choices = { 2, 3, 3, 3, 4 }, -- сколько кучек на выбор
			maxStones = { 3, 4, 5, 7, 10 },
			hintAfterSec = { 10, 10, 12, 12, 14 },
			missCooldown = { 1.6, 1.4, 1.2, 1.1, 1 },
		},
	},

	--[[
		«Ягодная поляна» (docs/16-MATH.md § 3.2): собрать столько ягод, сколько
		сказал голос, и отнести в корзинку. Лишние ягоды на кустах есть всегда —
		иначе задание решалось бы «собери всё, что видишь».
	]]
	berries = {
		id = "berries",
		title = "Ягодная поляна",
		voInstruction = "instr_berries",
		trains = { "count" },
		minLetters = 0,
		maxSeconds = 150,
		params = {
			rounds = { 3, 3, 4, 4, 5 },
			extra = { 2, 3, 3, 4, 5 }, -- сколько ягод на кустах сверх нужного
			missCooldown = { 1.6, 1.4, 1.2, 1.1, 1 },
		},
	},
}

local Module = {}

Module.all = Challenges

function Module.get(id: string): ChallengeMeta?
	return Challenges[id]
end

function Module.expect(id: string): ChallengeMeta
	local meta = Challenges[id]
	assert(meta, `Challenges: неизвестное испытание "{id}"`)
	return meta
end

function Module.ids(): { string }
	local ids: { string } = {}
	for id in Challenges do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return Module
