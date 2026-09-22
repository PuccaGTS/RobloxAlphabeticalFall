--!nocheck
--[[
	Ребёнок ногами: дойти до каждого пада и в каждый портал, постоять,
	посмотреть, запустилось ли занятие и стоит ли персонаж на полу.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

local TARGETS = {
	"Pad_letter_rain",
	"Pad_berries",
	"Pad_bubbles",
	"Pad_mirror",
	"Pad_alphabet_ladder",
	"Pad_scales",
	"Pad_lava_floor",
	"PortalVeil_letters",
	"PortalVeil_math",
}

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	for _ = 1, 80 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	note(
		"profile "
			.. tostring(ProfileService.get(player) ~= nil)
			.. " character "
			.. tostring(player.Character ~= nil)
	)
	local only = workspace:GetAttribute("ZZ_Only")

	for _, name in TARGETS do
		if only and not name:find(only) then
			continue
		end
		local target = workspace.Hub:FindFirstChild(name)
		if not target then
			note("NO TARGET " .. name)
			continue
		end
		Teleport.to(player, Teleport.HUB)
		task.wait(2.5)
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		humanoid:MoveTo(target.Position)
		note(`>> walk to {name}`)
		local started = false
		for i = 1, 40 do
			task.wait(0.5)
			if ChallengeService.isBusy(player) then
				started = true
				note(string.format("   started after %.1fs", i * 0.5))
				break
			end
			if i % 6 == 0 then
				humanoid:MoveTo(target.Position)
			end
		end
		if not started then
			local root = player.Character.HumanoidRootPart
			note(
				string.format(
					"   NOT STARTED, root at %s, target at %s",
					tostring(root.Position),
					tostring(target.Position)
				)
			)
			continue
		end
		for i = 1, 12 do
			task.wait(0.5)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if i % 2 == 0 then
				note(
					string.format(
						"   t%.1f pos %s busy=%s",
						i * 0.5,
						root and tostring(root.Position) or "-",
						tostring(ChallengeService.isBusy(player))
					)
				)
			end
		end
		pcall(ChallengeService.abort, player)
		task.wait(3)
	end
end
