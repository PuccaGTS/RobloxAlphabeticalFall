--!strict
--[[
	Точка входа сервера.

	Порядок запуска важен: сначала Remote-объекты, потом сервисы, потом приём игроков.
	Пока сервисы не написаны, здесь остаётся проверка целостности конфигов —
	она сразу покажет в логе, чего не хватает контенту.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)
local Letters = require(Shared.Config.Letters)
local Syllables = require(Shared.Config.Syllables)
local Words = require(Shared.Config.Words)
local Islands = require(Shared.Config.Islands)
local AudioRegistry = require(Shared.Config.AudioRegistry)

local Services = script:WaitForChild("Services")
local ProfileService = require(Services.ProfileService)
local EconomyService = require(Services.EconomyService)
local ProgressService = require(Services.ProgressService)
local ChallengeService = require(Services.ChallengeService)

-- Порядок важен: сначала Remote-объекты, потом сервисы, потом приём игроков.
RemoteDefs.init()

local function reportContentState()
	print(
		string.format(
			"[AlphabetFall] контент: букв %d, слогов %d, слов %d, островов %d",
			Letters.count(),
			Syllables.count(),
			#Words.ids(),
			Islands.count()
		)
	)

	local unregistered = AudioRegistry.unregistered()
	if #unregistered > 0 then
		warn(
			`[AlphabetFall] в реестре озвучки нет {#unregistered} ключей: `
				.. table.concat(unregistered, ", ")
		)
	end

	local pending = AudioRegistry.pending()
	if #pending > 0 then
		print(
			string.format(
				"[AlphabetFall] озвучка не загружена для %d из %d реплик — игра работает молча",
				#pending,
				#AudioRegistry.requiredKeys()
			)
		)
	end
end

reportContentState()

EconomyService.start()
ProgressService.start()
ChallengeService.start()
ProfileService.start() -- последним: он сразу начинает принимать игроков

--[[
	TODO (веха 1, docs/12-ROADMAP.md):
	  ShopService       — покупки и инвентарь
	  CosmeticsService  — надевание аксессуаров и питомцев при CharacterAdded
	  Испытания «Эхо-буква» и «Мост слогов» по тому же контракту, что LetterRain
]]

print("[AlphabetFall] сервер запущен")
