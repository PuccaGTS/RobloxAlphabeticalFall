--!strict
--[[
	Точка входа сервера.

	Порядок запуска важен: сначала Remote-объекты, потом сервисы, потом приём игроков.
	Пока сервисы не написаны, здесь остаётся проверка целостности конфигов —
	она сразу покажет в логе, чего не хватает контенту.
]]

local Players = game:GetService("Players")
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
local VenueService = require(Services.VenueService)
local LavaFloorService = require(Services.LavaFloorService)
local ParentService = require(Services.ParentService)
local TutorialService = require(Services.TutorialService)
local PlayLimitService = require(Services.PlayLimitService)
local PetService = require(Services.PetService)
local DailyLetterService = require(Services.DailyLetterService)
local SafetyService = require(Services.SafetyService)
local ChestService = require(Services.ChestService)
local DevService = require(Services.DevService)
local DecorService = require(Services.DecorService)
local RentalService = require(Services.RentalService)
local MailService = require(Services.MailService)
local QuestService = require(Services.QuestService)
local Teleport = require(script:WaitForChild("World").Teleport)

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

--[[
	Пока мир не построен, персонажей нет. Раньше ребёнок появлялся на третьей
	секунде, а площадь достраивалась к десятой: персонаж падал сквозь пустоту
	или шаблон Studio. Появление включается в конце запуска.
]]
Players.CharacterAutoLoads = false

-- Чужое из Workspace убирается ДО постройки: иначе чистка снесла бы поляны.
WorldService.clearForeignWorld()
-- Модели декора грузятся все сразу, пока ничего не построено (не дольше 6 секунд).
DecorService.preload(6)

--[[
	Сервис, упавший при запуске, не должен останавливать остальные: без
	ProfileService не работает ни одно занятие, а он запускается последним.
]]
local function start(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(`[AlphabetFall] {name} не запустился: {err}`)
	end
end

start("SafetyService", SafetyService.start) -- первым: чат выключается раньше, чем кто-то успеет зайти
start("Teleport", Teleport.start) -- страж падения: смерти в игре нет нигде
start("EconomyService", EconomyService.start)
start("ProgressService", ProgressService.start)
start("ChallengeService", ChallengeService.start)
start("TunnelService", TunnelService.start) -- подписывается на хуки испытаний, поэтому после ChallengeService
start("VenueService", VenueService.start) -- поляны занятий: одно задание — одна локация
start("LavaFloorService", LavaFloorService.start) -- раунды «Пол — это лава!»: после полян, точка сцены уже в задании
start("CosmeticsService", CosmeticsService.start)
start("ShopService", ShopService.start)
start("WorldService", WorldService.start)
start("BaseService", BaseService.start) -- после мира: участки встают вокруг уже построенной площади
start("ChestService", ChestService.start) -- сундуки в парке между площадью и участками
start("RentalService", RentalService.start) -- прокат в парке: круги у ларька уже стоят
start("ParentService", ParentService.start)
start("DevService", DevService.start) -- полёт и звёзды для проверки: только Studio и владелец места
start("TutorialService", TutorialService.start) -- подписывается на хуки испытаний и магазина
start("PlayLimitService", PlayLimitService.start) -- сторож старта испытаний: время на сегодня
start("PetService", PetService.start) -- подписывается на смену статусов букв
start("MailService", MailService.start) -- открытки от буквят: тоже по смене статусов букв
start("DailyLetterService", DailyLetterService.start) -- подписывается на хуки испытаний
start("QuestService", QuestService.start) -- задания дня: хуки испытаний, стройки, магазина, сундуков
start("ProfileService", ProfileService.start) -- последним: он сразу начинает принимать игроков

Players.CharacterAutoLoads = true
for _, player in Players:GetPlayers() do
	if not player.Character then
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end

print("[AlphabetFall] сервер запущен")
