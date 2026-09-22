--!nocheck
-- Испытания на полянах глазами ребёнка: запуск и снимок от входа и чуть сверху.
-- ZZ_ONLY=letter_rain,bubbles — какие снимать.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Venues = require(ReplicatedStorage.Shared.Config.Venues)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)

	local only = workspace:GetAttribute("ZZ_Only")
	local ids = if only then string.split(only, ",") else { "letter_rain", "bubbles", "alphabet_ladder" }
	for _, id in ids do
		if id == "pet" then
			-- Буквёнок А: буква освоена прямо в профиле, питомец летит за персонажем.
			local PetService = require(Services.PetService)
			ProfileService.update(player, function(p)
				p.letters.a = p.letters.a or {}
				p.letters.a.mastery = 3
			end)
			PetService.grant(player, "a")
			task.wait(4)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local look = root.CFrame
				_G.ZZ_Shot(
					player,
					"ch_pet",
					CFrame.lookAt(
						(look * CFrame.new(4, 3, -12)).Position,
						look.Position + Vector3.new(0, 2, 0)
					),
					60
				)
			end
			continue
		end
		ChallengeService.abort(player)
		local entry = Venues.entry(id)
		Teleport.to(player, entry)
		task.wait(2.5)
		ChallengeService.startFor(player, id)
		task.wait(4)
		note(`{id} busy={ChallengeService.isBusy(player)}`)
		local center = Venues.center(id)
		_G.ZZ_Shot(
			player,
			`ch_{id}`,
			CFrame.lookAt(entry.Position + Vector3.new(0, 4, 6), center + Vector3.new(0, 6, 0)),
			70
		)
	end
	ChallengeService.abort(player)
end
