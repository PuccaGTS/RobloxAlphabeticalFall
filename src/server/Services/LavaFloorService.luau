--!nonstrict
--[[
	Раунды «Пол — это лава!» (Challenges/LavaFloor): ведёт расписание на сервере
	и в момент лавы смотрит, на какой плите стоит ребёнок.

	Расписание считается от серверных часов: момент старта уходит в задании
	(`params.startAt`), и клиент рисует те же раунды сам — без сообщений
	на каждый раунд и без рассинхрона.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Venues = require(Shared.Config.Venues)

local ChallengeService = require(script.Parent.ChallengeService)
local LavaFloor = require(script.Parent.Parent.Challenges.LavaFloor)

local LavaFloorService = {}

-- Чуть позже, чем загорается лава: ребёнок, запрыгнувший в последний миг, успел.
local GRACE = 0.25

local tokens: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function run(player: Player, spec: any, token: number)
	local params = spec.params
	local stage = params.stage or Venues.stage(LavaFloor.id)
	local function alive(): boolean
		return tokens[player] == token and ChallengeService.isBusy(player)
	end

	for round = 1, #params.rounds do
		local at = params.startAt + LavaFloor.lavaAt(params, round) + GRACE
		task.wait(math.max(0, at - workspace:GetServerTimeNow()))
		if not alive() then
			return
		end
		local root = rootOf(player)
		local tile = nil
		if root then
			local position = stage:PointToObjectSpace(root.Position)
			-- Выше плит на прыжок — всё равно над своей плитой: в прыжке ребёнок не виноват.
			if position.Y > -2 and position.Y < 12 then
				tile = LavaFloor.tileAt(position)
			end
		end
		ChallengeService.submitAction(player, { kind = "round", round = round, tile = tile, token = token })
	end

	task.wait(LavaFloor.LAVA_SECONDS + 0.5)
	if alive() then
		ChallengeService.submitAction(player, { kind = "end", token = token })
	end
end

function LavaFloorService.start()
	ChallengeService.onStarted(function(player: Player, spec: any)
		if spec.challengeId ~= LavaFloor.id then
			return
		end
		local token = Random.new():NextInteger(1, 2 ^ 30)
		tokens[player] = token
		spec.params.startAt = workspace:GetServerTimeNow()
		-- Токен кладётся в состояние, а не в задание: клиенту его знать незачем.
		ChallengeService.setStateField(player, "lavaToken", token)
		task.spawn(run, player, spec, token)
	end)

	ChallengeService.onFinished(function(player: Player, spec: any)
		if spec.challengeId == LavaFloor.id then
			tokens[player] = nil
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		tokens[player] = nil
	end)
end

return LavaFloorService
