--!strict
--[[
	Параметры испытаний по уровням сложности 1..5.
	Ни одного «магического числа» в коде испытаний — только отсюда.
	См. docs/03-CHALLENGES.md и docs/09-DATA-SCHEMA.md § 8.
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
		trains = { "recognize", "sound_to_letter" },
		minLetters = 2,
		maxSeconds = 120,
		params = {
			targetCount = { 5, 5, 6, 7, 8 },
			distractors = { 1, 2, 3, 4, 4 },
			fallSpeed = { 6, 8, 10, 12, 14 }, -- studs/sec
			spawnInterval = { 1.2, 1.0, 0.9, 0.75, 0.6 }, -- sec
			hintAfterSec = { 6, 6, 8, 10, 12 },
			-- Пауза после промаха: «сачок опустился». Не наказание, а плата временем —
			-- за неё ребёнок слышит тронутую букву и снова цель. Без неё задание
			-- решается перебором, и слушать становится незачем.
			missCooldown = { 1.4, 1.2, 1.1, 1.0, 0.9 },
		},
	},

	echo_letter = {
		id = "echo_letter",
		title = "Эхо-буква",
		voInstruction = "instr_echo_letter",
		trains = { "letter_to_sound" },
		minLetters = 1,
		maxSeconds = 90,
		params = {
			repeats = { 3, 3, 3, 4, 4 },
			listenWindowSec = { 4, 4, 3.5, 3, 3 }, -- сколько ждём ребёнка перед подсказкой
			holdBonusSec = { 3, 3, 3, 3, 3 }, -- «тянучка» в режиме B, см. docs/06-MICROPHONE.md
		},
	},

	syllable_bridge = {
		id = "syllable_bridge",
		title = "Мост слогов",
		voInstruction = "instr_syllable_bridge",
		trains = { "letter_to_sound", "blend" },
		minLetters = 2,
		maxSeconds = 150,
		params = {
			sections = { 4, 4, 5, 5, 6 }, -- сколько слогов в мосту
			vowelChoices = { 2, 3, 3, 4, 4 }, -- из скольких гласных выбирать
			hintAfterSec = { 8, 8, 10, 12, 12 },
		},
	},

	bubbles = {
		id = "bubbles",
		title = "Пузыри",
		voInstruction = "instr_bubbles",
		trains = { "recognize", "sound_to_letter" },
		minLetters = 2,
		maxSeconds = 100,
		params = {
			targetCount = { 3, 3, 4, 4, 5 },
			totalBubbles = { 8, 10, 12, 14, 16 },
			riseSpeed = { 2, 2.5, 3, 3.5, 4 },
			hintAfterSec = { 7, 7, 9, 10, 12 },
		},
	},

	build_word = {
		id = "build_word",
		title = "Собери слово",
		voInstruction = "instr_build_word",
		trains = { "recognize", "blend", "word" },
		minLetters = 3,
		maxSeconds = 180,
		params = {
			wordLength = { 3, 3, 4, 4, 5 },
			showImage = { 1, 1, 1, 1, 0 }, -- 0 = только по звучанию
			hintAfterSec = { 10, 10, 12, 14, 15 },
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
