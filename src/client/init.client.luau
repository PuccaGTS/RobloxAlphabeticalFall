--!nonstrict
--[[
	Точка входа клиента. Только сборка контроллеров — никакой игровой логики здесь.
	Решения о верности ответов и наградах принимает сервер (docs/07-TECH-ARCH.md § 3).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)
local Letters = require(Shared.Config.Letters)

local Controllers = script:WaitForChild("Controllers")
local AudioController = require(Controllers.AudioController)
local ChallengeController = require(Controllers.ChallengeController)
local HUD = require(script:WaitForChild("UI").HUD)

AudioController.init()
ChallengeController.init()

HUD.build({
	onRepeat = function()
		AudioController.repeatLast()
	end,
	-- ВРЕМЕННО: прямой запуск испытания до появления хаба с порталами островов
	onStart = function()
		ChallengeController.start("letter_rain")
	end,
})

-- Срез профиля от сервера: единственный источник состояния для интерфейса.
RemoteDefs.event("ProfileSnapshot").OnClientEvent:Connect(function(snapshot: any)
	if typeof(snapshot) ~= "table" then
		return
	end
	HUD.setStars(snapshot.stars or 0)
end)

-- Сервер просит проиграть реплику: единственный канал озвучки между сервером и клиентом.
RemoteDefs.event("PlayVO").OnClientEvent:Connect(function(key: string, interrupt: boolean?)
	if typeof(key) ~= "string" then
		return
	end
	if interrupt == true then
		AudioController.interrupt(key)
	else
		AudioController.speak(key)
	end
end)

-- Предзагружаем звуки букв первого острова: задержка перед звуком буквы недопустима.
task.defer(function()
	local keys: { string } = {}
	for _, id in Letters.byIsland(1) do
		local letter = Letters.expect(id)
		table.insert(keys, letter.vo.sound)
		if letter.vo.long then
			table.insert(keys, letter.vo.long)
		end
	end
	AudioController.preload(keys)
end)

print("[AlphabetFall] клиент запущен")
