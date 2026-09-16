--!nonstrict
--[[
	Инструменты разработчика: звёзды на счёт и перенос по локациям.

	Нужны, чтобы проверять мир и магазин, не проходя занятия по кругу:
	облететь поляны и туннели, купить редкую вещь и посмотреть, как она выглядит.

	Доступны только в Studio и владельцу места на боевом сервере. Ребёнку
	они не показываются никогда: сервер ставит игроку атрибут DevTools, и только
	по нему клиент строит панель. Каждая команда проверяется здесь заново —
	атрибут для сервера не доказательство.

	Полёт живёт целиком на клиенте (Controllers/DevController): физика персонажа
	и так клиентская, серверу проверять там нечего.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)
local Venues = require(Shared.Config.Venues)

local ProfileService = require(script.Parent.ProfileService)
local ChallengeService = require(script.Parent.ChallengeService)
local BaseService = require(script.Parent.BaseService)
local RateLimiter = require(script.Parent.RateLimiter)
local Teleport = require(script.Parent.Parent.World.Teleport)

local DevService = {}

-- Сколько звёзд можно выдать за раз: кнопки панели, а не произвольное число.
local STAR_AMOUNTS: { [number]: boolean } = { [100] = true, [1000] = true }

function DevService.allowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function targetOf(player: Player, target: any): CFrame?
	if target == "hub" then
		return Teleport.HUB
	elseif target == "home" then
		return BaseService.homeCFrame(player)
	elseif typeof(target) == "string" and Venues.get(target) then
		return Venues.entry(target)
	end
	return nil
end

local function onCommand(player: Player, command: any)
	if not DevService.allowed(player) or typeof(command) ~= "table" then
		return
	end
	if not RateLimiter.allow(player, "DevCommand", RemoteDefs.RATE_LIMITS.DevCommand) then
		return
	end

	if command.kind == "stars" and STAR_AMOUNTS[command.amount] then
		ProfileService.update(player, function(profile)
			profile.stars += command.amount
		end)
		print(`[Dev] {player.Name}: +{command.amount} ⭐`)
	elseif command.kind == "teleport" then
		local cframe = targetOf(player, command.target)
		if not cframe then
			return
		end
		if ChallengeService.isBusy(player) then
			ChallengeService.abort(player)
		end
		Teleport.to(player, cframe)
	end
end

function DevService.start()
	local function mark(player: Player)
		if DevService.allowed(player) then
			player:SetAttribute("DevTools", true)
		end
	end
	Players.PlayerAdded:Connect(mark)
	for _, player in Players:GetPlayers() do
		mark(player)
	end

	RemoteDefs.event("DevCommand").OnServerEvent:Connect(onCommand)
end

return DevService
