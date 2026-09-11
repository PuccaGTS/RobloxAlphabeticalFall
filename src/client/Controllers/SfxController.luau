--!strict
--[[
	Звуковые эффекты. Каталог — Config/Sfx.

	Отдельно от AudioController, и это не дублирование, а разное поведение:
	реплики выстраиваются в очередь и никогда не накладываются (иначе ребёнок
	слышит кашу вместо задания), а эффекты, наоборот, обязаны звучать сразу
	и поверх друг друга — иначе «поймал» приходит через секунду после того,
	как поймал, и перестаёт быть обратной связью.

	Громкость эффектов подчинена группе SFX, которую держит AudioController:
	на время любой реплики она приглушается вместе с музыкой, и голос остаётся
	слышен поверх всего.
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Sfx = require(Shared.Config.Sfx)

local AudioController = require(script.Parent.AudioController)

local SfxController = {}

--[[
	Один и тот же эффект чаще, чем раз в столько секунд, не повторяем.

	Нужно на воротах: касание триггера прилетает несколько раз подряд, и без
	этого «поймал» звучит очередью из трёх пингов.
]]
local REPEAT_GUARD = 0.08

local lastPlayed: { [string]: number } = {}

function SfxController.play(key: string): boolean
	local effect = Sfx.get(key)
	if not effect then
		warn(`[SfxController] неизвестный эффект: {key}`)
		return false
	end

	local now = os.clock()
	if lastPlayed[key] and now - lastPlayed[key] < REPEAT_GUARD then
		return false
	end
	lastPlayed[key] = now

	local sound = Instance.new("Sound")
	sound.Name = `Sfx_{key}`
	sound.SoundId = effect.id
	sound.Volume = effect.volume
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = SoundService
	sound:Play()

	-- Убираем с запасом: звук может не догрузиться, и тогда Ended не придёт вовсе.
	Debris:AddItem(sound, effect.seconds + 1)
	return true
end

function SfxController.init()
	AudioController.init()
end

return SfxController
