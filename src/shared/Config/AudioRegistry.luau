--!strict
--[[
	Реестр озвучки: vo_key -> rbxassetid.
	ЕДИНСТВЕННОЕ место, где живут ID аудио. В коде испытаний и UI сырых ID быть не должно.

	Пока озвучка не записана и не загружена, значения пустые: игра работает,
	но проигрывает тишину и пишет предупреждение (один раз на ключ).

	Порядок работы: записали → загрузили на аккаунт ГРУППЫ → вписали id сюда → коммит.
	См. docs/05-AUDIO-VO.md и docs/10-CONTENT-PIPELINE.md.
]]

local Letters = require(script.Parent.Letters)
local Syllables = require(script.Parent.Syllables)
local Words = require(script.Parent.Words)
local Challenges = require(script.Parent.Challenges)

local AudioRegistry = {}

-- Когда true, отсутствие озвучки роняет сборку/тест вместо тихого предупреждения.
-- Включить перед релизом, когда все реплики записаны.
AudioRegistry.STRICT = false

AudioRegistry.PRAISE_COUNT = 8 -- praise_01 .. praise_08 (MVP)
AudioRegistry.RETRY_COUNT = 5
AudioRegistry.HINT_COUNT = 3

--[[
	Заполняется по мере загрузки аудио. Формат: ["snd_m"] = "rbxassetid://123456".
	Пустая строка = реплика ещё не записана.
]]
local ids: { [string]: string } = {
	-- === Звуки букв (записывать первыми) ===
	snd_a = "",
	snd_u = "",
	snd_o = "",
	snd_i = "",
	snd_m = "",
	snd_p = "",
	snd_b = "",
	snd_t = "",
	snd_n = "",

	-- === Растянутые звуки для «Эхо-буквы» ===
	snd_long_a = "",
	snd_long_u = "",
	snd_long_o = "",
	snd_long_i = "",
	snd_long_m = "",
	snd_long_n = "",

	-- === Инструкции испытаний ===
	instr_letter_rain = "",
	instr_echo_letter = "",
	instr_syllable_bridge = "",
	instr_bubbles = "",
	instr_build_word = "",

	-- === Сюжет и навигация ===
	story_intro = "",
	story_island1_intro = "",
	story_island2_intro = "",
	story_island3_intro = "",

	-- === UI ===
	ui_shop = "",
	ui_stars = "",
	ui_goodbye = "",
	ui_rest_reminder = "",
}

-- Похвала/коррекция/подсказки генерируются пачкой: praise_01..praise_08 и т.д.
for i = 1, AudioRegistry.PRAISE_COUNT do
	ids[string.format("praise_%02d", i)] = ""
end
for i = 1, AudioRegistry.RETRY_COUNT do
	ids[string.format("retry_%02d", i)] = ""
end
for i = 1, AudioRegistry.HINT_COUNT do
	ids[string.format("hint_%02d", i)] = ""
end

-- Слоги и слова: ключи создаются из конфигов, чтобы список нельзя было забыть обновить.
for _, syllableId in Syllables.ids() do
	local key = Syllables.expect(syllableId).vo
	if ids[key] == nil then
		ids[key] = ""
	end
end
for _, wordId in Words.ids() do
	local word = Words.expect(wordId)
	if ids[word.vo] == nil then
		ids[word.vo] = ""
	end
	if ids[word.voSyllabic] == nil then
		ids[word.voSyllabic] = ""
	end
end

AudioRegistry.ids = ids

--[[
	Все ключи, которые игра реально попросит проиграть. Считается из конфигов —
	именно этот список сверяет тест ConfigIntegrity.
]]
function AudioRegistry.requiredKeys(): { string }
	local set: { [string]: boolean } = {}

	for id in Letters.all do
		local letter = Letters.expect(id)
		set[letter.vo.sound] = true
		if letter.vo.long then
			set[letter.vo.long] = true
		end
		-- vo.name нужен только на 8-м острове, в обязательные для MVP не включаем
	end

	for _, id in Syllables.ids() do
		set[Syllables.expect(id).vo] = true
	end

	for _, id in Words.ids() do
		local word = Words.expect(id)
		set[word.vo] = true
		set[word.voSyllabic] = true
	end

	for _, id in Challenges.ids() do
		set[Challenges.expect(id).voInstruction] = true
	end

	local keys: { string } = {}
	for key in set do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Ключи, объявленные в конфигах, но не заведённые в реестре вовсе.
function AudioRegistry.unregistered(): { string }
	local missing: { string } = {}
	for _, key in AudioRegistry.requiredKeys() do
		if AudioRegistry.ids[key] == nil then
			table.insert(missing, key)
		end
	end
	return missing
end

-- Ключи, заведённые, но ещё без загруженного аудио.
function AudioRegistry.pending(): { string }
	local pending: { string } = {}
	for _, key in AudioRegistry.requiredKeys() do
		if AudioRegistry.ids[key] == "" then
			table.insert(pending, key)
		end
	end
	return pending
end

local warned: { [string]: boolean } = {}

--[[
	Возвращает готовый к проигрыванию asset id либо nil.
	nil означает «реплики ещё нет» — вызывающий код обязан это пережить без ошибки.
]]
function AudioRegistry.resolve(key: string): string?
	local id = AudioRegistry.ids[key]
	if id == nil then
		if AudioRegistry.STRICT then
			error(`AudioRegistry: ключ "{key}" не объявлен`)
		end
		if not warned[key] then
			warned[key] = true
			warn(`[AudioRegistry] неизвестный ключ озвучки: {key}`)
		end
		return nil
	end
	if id == "" then
		if not warned[key] then
			warned[key] = true
			warn(`[AudioRegistry] озвучка ещё не загружена: {key}`)
		end
		return nil
	end
	return id
end

return AudioRegistry
