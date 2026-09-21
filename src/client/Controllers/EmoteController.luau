--!strict
--[[
	Танцы и жесты персонажа (Config/Emotes). Анимация играет на клиенте,
	а Roblox сам показывает её другим: персонаж принадлежит своему игроку.

	Танец идёт, пока ребёнок стоит; шагнул или прыгнул — танец кончился.
	На танец и «ура» буквята хозяина прыгают с оборотом и сыплют искрами.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Emotes = require(Shared.Config.Emotes)
local PetController = require(script.Parent.PetController)

local EmoteController = {}

local player = Players.LocalPlayer
local track: AnimationTrack? = nil
local playing: string? = nil
local cheerAt = 0

local function stop()
	if track then
		track:Stop(0.2)
		track = nil
	end
	playing = nil
end

function EmoteController.play(id: string): boolean
	local emote = Emotes.get(id)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not emote or not humanoid or not animator or humanoid.Health <= 0 then
		return false
	end
	stop()
	local animation = Instance.new("Animation")
	local assetId = if humanoid.RigType == Enum.HumanoidRigType.R6 then emote.r6 else emote.r15
	animation.AnimationId = `rbxassetid://{assetId}`
	local loaded = animator:LoadAnimation(animation)
	loaded.Priority = Enum.AnimationPriority.Action
	loaded.Looped = emote.looped
	loaded:Play(0.2)
	track = loaded
	playing = id
	loaded.Stopped:Connect(function()
		if track == loaded then
			track = nil
			playing = nil
		end
	end)
	if Emotes.PETS_JOIN[id] then
		cheerAt = os.clock()
		PetController.cheer()
	end
	return true
end

function EmoteController.playing(): string?
	return playing
end

function EmoteController.init()
	RunService.Heartbeat:Connect(function()
		if not track then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.MoveDirection.Magnitude > 0.1 or humanoid.Jump then
			stop()
			return
		end
		-- Пока хозяин танцует, буквята подпрыгивают снова каждые несколько секунд.
		if playing and Emotes.PETS_JOIN[playing] and os.clock() - cheerAt > 3 then
			cheerAt = os.clock()
			PetController.cheer()
		end
	end)
	player.CharacterAdded:Connect(stop)
end

return EmoteController
