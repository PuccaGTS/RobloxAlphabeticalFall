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
local Stages = require(Shared.Config.Stages)
local Obstacles = require(Shared.Config.Obstacles)
local AudioRegistry = require(Shared.Config.AudioRegistry)

local Services = script:WaitForChild("Services")
local ProfileService = require(Services.ProfileService)
local EconomyService = require(Services.EconomyService)
local ProgressService = require(Services.ProgressService)
local ChallengeService = require(Services.ChallengeService)
local CosmeticsService = require(Services.CosmeticsService)
local ShopService = require(Services.ShopService)
local WorldService = require(Services.WorldService)
local BaseService = require(Services.BaseService)
local TunnelService = require(Services.TunnelService)
local ParentService = require(Services.ParentService)
local TutorialService = require(Services.TutorialService)
local PlayLimitService = require(Services.PlayLimitService)
local PetService = require(Services.PetService)
local DailyLetterService = require(Services.DailyLetterService)
local SafetyService = require(Services.SafetyService)

-- Порядок важен: сначала Remote-объекты, потом сервисы, потом приём игроков.
RemoteDefs.init()

local function reportContentState()
	print(
		string.format(
			"[AlphabetFall] контент: букв %d, ступеней %d, препятствий %d",
			Letters.count(),
			Stages.count(),
			#Obstacles.ids()
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

SafetyService.start() -- первым: чат выключается раньше, чем кто-то успеет зайти
EconomyService.start()
ProgressService.start()
ChallengeService.start()
TunnelService.start() -- подписывается на хуки испытаний, поэтому после ChallengeService
CosmeticsService.start()
ShopService.start()
WorldService.start()
BaseService.start() -- после мира: участки встают вокруг уже построенной площади
ParentService.start()
TutorialService.start() -- подписывается на хуки испытаний и магазина
PlayLimitService.start() -- сторож старта испытаний: время на сегодня
PetService.start() -- подписывается на смену статусов букв
DailyLetterService.start() -- подписывается на хуки испытаний
ProfileService.start() -- последним: он сразу начинает принимать игроков

print("[AlphabetFall] сервер запущен")
