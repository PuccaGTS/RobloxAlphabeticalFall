--!nocheck
--[[
	Звуки библиотеки грузятся у клиента: ZZ_ONLY=sfx_run_,amb_run_ — префиксы ключей
	AudioRegistry (по умолчанию все звуки аттракционов). Отчёт — строка SOUNDS.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(_player, note)
	local AudioRegistry = require(ReplicatedStorage.Shared.Config.AudioRegistry)
	-- Зонд клиента подписывается на метки только после проверки мешей (~20 с).
	task.wait(24)
	local prefixes = workspace:GetAttribute("ZZ_Only") or "sfx_run_,amb_run_"
	local keys = {}
	for key, id in AudioRegistry.ids do
		for prefix in string.gmatch(prefixes, "[^,]+") do
			if id ~= "" and string.sub(key, 1, #prefix) == prefix then
				table.insert(keys, key)
				break
			end
		end
	end
	table.sort(keys)
	note(`checking {#keys} sounds`)
	workspace:SetAttribute("ZZ_SoundCheck", table.concat(keys, ","))
	task.wait(15)
end
