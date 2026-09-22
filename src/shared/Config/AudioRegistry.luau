--!strict
--[[
	Реестр озвучки: vo_key -> rbxassetid.
	ЕДИНСТВЕННОЕ место, где живут ID аудио. В коде испытаний и UI сырых ID быть не должно.

	Пока озвучка не записана и не загружена, значения пустые: игра работает,
	но проигрывает тишину и пишет предупреждение (один раз на ключ).

	Порядок работы: записали → загрузили на аккаунт ГРУППЫ → вписали id сюда → коммит.
	См. docs/05-AUDIO-VO.md и docs/10-CONTENT-PIPELINE.md.

	Реплик стало мало и они простые: 33 названия букв плюс общий набор инструкций,
	похвал и подсказок. Никаких изолированных звуков и слитных слогов — почему,
	написано в docs/05-AUDIO-VO.md § 1.
]]

local Letters = require(script.Parent.Letters)
local Challenges = require(script.Parent.Challenges)
local Stages = require(script.Parent.Stages)
local MathConfig = require(script.Parent.Math)
local Tutorial = require(script.Parent.Parent.Logic.Tutorial)

local AudioRegistry = {}

-- Когда true, отсутствие озвучки роняет сборку/тест вместо тихого предупреждения.
-- Включить перед релизом, когда все реплики записаны.
AudioRegistry.STRICT = false

AudioRegistry.PRAISE_COUNT = 8 -- praise_01 .. praise_08
AudioRegistry.RETRY_COUNT = 5
AudioRegistry.HINT_COUNT = 3

--[[
	Заполняется по мере загрузки аудио. Формат: ["letter_m"] = "rbxassetid://123456".
	Пустая строка = реплика ещё не записана.
]]
local ids: { [string]: string } = {
	-- === Инструкции испытаний ===
	-- Инструкция всегда общая и заканчивается на «вот эту букву:», после чего
	-- играет letter_*. Так 6 файлов покрывают все 33 буквы вместо 198 комбинаций.
	instr_letter_rain = "",
	instr_alphabet_ladder = "",
	instr_tunnel_run = "",
	instr_lava_floor = "",
	instr_bubbles = "",
	instr_mirror = "",
	instr_math_gates = "",
	instr_scales = "",
	instr_berries = "",

	-- === Сюжет и навигация ===
	story_intro = "",
	story_meet_letter = "", -- «Познакомься! Это…» + letter_*
	story_stage_open = "", -- «Открылись новые буквы!»
	story_stage_done = "", -- «Ты выучил всю ступень!»

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

-- Названия букв: ключи создаются из справочника, чтобы список нельзя было забыть обновить.
for letterId in Letters.all do
	local key = Letters.expect(letterId).vo.name
	if ids[key] == nil then
		ids[key] = ""
	end
end

--[[
	Математика: десять чисел и куски фраз, из которых собирается любая задача
	(«Сколько будет» + «два» + «плюс» + «два»). Ключи берутся из Config/Math,
	чтобы список нельзя было забыть обновить, а сама сборка из кусков нужна ради
	объёма записи: реплика на каждый пример — это под три сотни файлов.
]]
for _, key in MathConfig.voKeys() do
	if ids[key] == nil then
		ids[key] = ""
	end
end

-- Музыка. Ключи живут в Config/Stages, но играет их клиент через этот же реестр —
-- иначе загруженным трекам некуда вписать id. Лупы готовит tools/audio/prepare_music.py,
-- соответствие файлов и id — в assets/audio/MANIFEST.csv.
for _, key in Stages.THEMES do
	if ids[key] == nil then
		ids[key] = ""
	end
end

--[[
	Звук из библиотеки Roblox: музыка (Config/Music), звуки природы (Config/Ambient)
	и гудок паровозика. Её не записывают и не загружают: APM Music и Pro Sound
	Effects лицензированы Roblox для всех опытов, id берутся из Creator Store как есть.
	В requiredKeys её нет — это не реплики, потолок сотни их не касается.
]]
local LIBRARY: { [string]: number } = {
	-- APM Music: спокойные инструментальные треки
	mus_lib_woodland = 9043323476,
	mus_lib_playground = 9046512235,
	mus_lib_garden = 9046598930,
	mus_lib_exploration = 9043326195,
	mus_lib_playful = 9042269449,
	mus_lib_crafts = 9040171127,
	mus_lib_shiny = 9046274992,
	-- Pro Sound Effects: природа и парк
	amb_birds = 9119383684, -- Sonoma Morning Birds, 128 с
	amb_fountain = 9120557577, -- Water Fountain, Huntington Park, 37 с
	amb_stream = 9120606523, -- Water Stream into Pool, 56 с
	amb_train_whistle = 9120223157, -- Toy Train Whistle, деревянный трёхтонный свисток
	sfx_camera_shutter = 17208312548, -- Roblox GUI - Camera Shutter: щелчок фото-зоны
	amb_carousel = 9046170527, -- APM Carousel Waltz (a): вальс шарманки у карусели, 115 с
	sfx_slide_whistle = 9119198473, -- Slide Whistle 7: мультяшный свисток на горке-спирали
	sfx_balloon_burner = 9114440283, -- Fire Whoosh 1: горелка воздушного шара, короткие вспышки
	sfx_fireworks = 9114447104, -- Fireworks Fast 2: свистящие ракеты и хлопки, салют за уровень
}
for key, assetId in LIBRARY do
	ids[key] = `rbxassetid://{assetId}`
end

AudioRegistry.ids = ids

--[[
	Все ключи, которые игра реально попросит проиграть. Считается из конфигов —
	именно этот список сверяет тест ConfigIntegrity.
]]
function AudioRegistry.requiredKeys(): { string }
	local set: { [string]: boolean } = {}

	for id in Letters.all do
		set[Letters.expect(id).vo.name] = true
	end

	for _, id in Challenges.ids() do
		set[Challenges.expect(id).voInstruction] = true
	end

	for _, stage in Stages.all do
		set[stage.music] = true
	end

	for _, key in MathConfig.voKeys() do
		set[key] = true
	end

	for _, key in { "story_intro", "story_meet_letter", "story_stage_open", "story_stage_done" } do
		set[key] = true
	end

	-- Лимит времени и отдых (docs/13-PARENT-MODE.md § 3): прощание и совет передохнуть.
	for _, key in { "ui_goodbye", "ui_rest_reminder" } do
		set[key] = true
	end

	-- Голос обучения первых минут: без него стрелка есть, а что делать — непонятно.
	for _, step in Tutorial.STEPS do
		if step.vo then
			set[step.vo] = true
		end
	end

	for i = 1, AudioRegistry.PRAISE_COUNT do
		set[string.format("praise_%02d", i)] = true
	end
	for i = 1, AudioRegistry.RETRY_COUNT do
		set[string.format("retry_%02d", i)] = true
	end
	for i = 1, AudioRegistry.HINT_COUNT do
		set[string.format("hint_%02d", i)] = true
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
