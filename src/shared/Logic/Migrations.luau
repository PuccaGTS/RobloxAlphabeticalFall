--!strict
--[[
	Миграции профиля. Чистая логика, покрыта тестами.

	Правила (docs/09-DATA-SCHEMA.md § 9):
	  · STEPS[v] переводит профиль версии v в версию v+1;
	  · шаги применяются последовательно, пропусков быть не может;
	  · поле не удаляется в той же версии, в которой перестало использоваться:
	    сначала перестаём писать, через релиз — удаляем.

	Миграция обязана быть терпимой к мусору: профиль мог быть сохранён старым билдом,
	повреждён или недописан. Падать нельзя — ребёнок останется без своих букв и шапок.
]]

local Types = require(script.Parent.Parent.Types)
local ProfileTemplate = require(script.Parent.Parent.Config.ProfileTemplate)

export type Step = (profile: any) -> ()

local Migrations = {}

--[[
	Шаги миграции. Пока структура профиля первой версии — шагов нет.
	Пример будущего шага:

		[1] = function(profile)
			profile.parent = profile.parent or { echoConsent = false }
		end,
]]
local STEPS: { [number]: Step } = {}

Migrations.STEPS = STEPS

--[[
	Приводит профиль к целевой версии.
	Возвращает профиль и число применённых шагов.

	steps можно подменить — это нужно тестам и ничему больше.
]]
function Migrations.apply(profile: any, targetVersion: number, steps: { [number]: Step }?): (any, number)
	local table_ = steps or STEPS
	local applied = 0

	if typeof(profile) ~= "table" then
		return profile, 0
	end

	if typeof(profile.version) ~= "number" then
		-- профиль без версии считаем самым первым
		profile.version = 1
	end

	while profile.version < targetVersion do
		local step = table_[profile.version]
		if step then
			local ok, err = pcall(step, profile)
			if not ok then
				warn(`[Migrations] шаг {profile.version} упал: {err}`)
			end
			applied += 1
		end
		profile.version += 1
	end

	return profile, applied
end

--[[
	Достраивает недостающие поля по шаблону. Страховка от профилей, сохранённых
	билдом, который поле ещё не писал, и от частично повреждённых данных.
	Существующие значения не трогает.
]]
function Migrations.fillDefaults(profile: any, now: number): Types.Profile
	local template = ProfileTemplate.new(now)

	if typeof(profile) ~= "table" then
		return template
	end

	for key, value in template :: any do
		if profile[key] == nil then
			profile[key] = value
		elseif typeof(value) == "table" and typeof(profile[key]) == "table" then
			-- один уровень вложенности: settings, parent, stats, equipped
			for subKey, subValue in value do
				if profile[key][subKey] == nil then
					profile[key][subKey] = subValue
				end
			end
		elseif typeof(profile[key]) ~= typeof(value) then
			-- тип не совпал: данные повреждены, берём значение по умолчанию
			warn(
				`[Migrations] поле "{key}" имело неверный тип, сброшено к значению по умолчанию`
			)
			profile[key] = value
		end
	end

	return profile :: Types.Profile
end

-- Полный проход: миграции + достройка полей. Именно это вызывает ProfileService.
function Migrations.normalize(profile: any, now: number): Types.Profile
	local migrated = Migrations.apply(profile, ProfileTemplate.VERSION)
	return Migrations.fillDefaults(migrated, now)
end

return Migrations
