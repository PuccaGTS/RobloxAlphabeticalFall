--!strict
--[[
	Громкость и субтитры из родительского режима. См. docs/13-PARENT-MODE.md § 3.

	Громкость выбирается ступенями, а не ползунком: ползунок на планшете
	дёргается под пальцем, а пять кнопок нажимаются с первого раза.

	Главное правило: голос всегда громче остального. Задание ребёнок получает
	голосом, и музыка, перекрикивающая «Буква М», ломает игру целиком. Поэтому:
	  · голос нельзя выключить — самая тихая ступень у него 25 %;
	  · музыка и эффекты не бывают громче голоса. Сделали голос тише —
	    они опускаются следом; подняли музыку выше голоса — она встаёт вровень.

	Чистая логика без Roblox API — покрыта тестами. Меняет настройки только
	родитель после входа по PIN (Services/ParentService).
]]

local Types = require(script.Parent.Parent.Types)

local SoundSettings = {}

SoundSettings.STEPS = { 0, 0.25, 0.5, 0.75, 1 }
SoundSettings.MIN_VOICE = 0.25
SoundSettings.KEYS = { "music", "sfx", "voice" }

function SoundSettings.isStep(value: any): boolean
	return typeof(value) == "number" and table.find(SoundSettings.STEPS, value) ~= nil
end

-- Музыку и эффекты — не громче голоса. Меняет таблицу на месте.
local function keepVoiceLoudest(settings: Types.Settings)
	settings.music = math.min(settings.music, settings.voice)
	settings.sfx = math.min(settings.sfx, settings.voice)
end

--[[
	Ставит громкость одной группы. Возвращает false на всё, что родитель
	выбрать не мог: чужой ключ, число не со ступени, выключенный голос.
]]
function SoundSettings.setVolume(settings: Types.Settings, key: string, value: any): boolean
	if not table.find(SoundSettings.KEYS, key) or not SoundSettings.isStep(value) then
		return false
	end
	if key == "voice" and value < SoundSettings.MIN_VOICE then
		return false
	end
	(settings :: any)[key] = value
	keepVoiceLoudest(settings)
	return true
end

--[[
	Настройки звука в профиле, приведённые в порядок: мусор становится значением
	по умолчанию, число не со ступени — ближайшей ступенью (из DataStore могут
	прийти старые умолчания 0.6 и 0.7 — это не мусор, а прежняя версия).
]]
function SoundSettings.sanitize(settings: Types.Settings, defaults: Types.Settings)
	for _, key in SoundSettings.KEYS do
		local value = (settings :: any)[key]
		if typeof(value) ~= "number" or value ~= value then
			value = (defaults :: any)[key]
		end
		local nearest = SoundSettings.STEPS[1]
		for _, step in SoundSettings.STEPS do
			if math.abs(step - value) < math.abs(nearest - value) then
				nearest = step
			end
		end
		(settings :: any)[key] = nearest
	end
	settings.voice = math.max(settings.voice, SoundSettings.MIN_VOICE)
	keepVoiceLoudest(settings)
	settings.subtitles = settings.subtitles == true
end

return SoundSettings
