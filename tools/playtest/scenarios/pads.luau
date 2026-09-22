--!nocheck
--[[
	Пады занятий и порталы: встать на каждый, дождаться переноса и посмотреть,
	стоит ли персонаж на месте или падает.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	for _ = 1, 60 do
		if ProfileService.get(player) and workspace:FindFirstChild("Hub") then
			break
		end
		task.wait(0.5)
	end
	note("profile " .. tostring(ProfileService.get(player) ~= nil))
	local hub = workspace:FindFirstChild("Hub")
	local names = {}
	for _, child in hub:GetChildren() do
		if child.Name:match("^Pad_") or child.Name:lower():match("portal") then
			table.insert(names, child.Name .. "(" .. child.ClassName .. ")")
		end
	end
	note("hub: " .. table.concat(names, ", "))

	local function root()
		local character = player.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	end

	local targets = {}
	for _, child in hub:GetChildren() do
		if child:IsA("BasePart") and child.Name:match("^Pad_") then
			table.insert(targets, child)
		end
	end
	table.sort(targets, function(a, b)
		return a.Name < b.Name
	end)

	for _, pad in targets do
		local r = root()
		if not r then
			note("no root")
			task.wait(2)
			continue
		end
		r.CFrame = pad.CFrame + Vector3.new(0, 4, 0)
		note(`>> stand on {pad.Name}`)
		for i = 1, 20 do
			task.wait(0.5)
			local rr = root()
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if i % 2 == 0 or i > 8 then
				note(
					string.format(
						"   t%.1f pos %s busy=%s hp=%s",
						i * 0.5,
						rr and tostring(rr.Position) or "-",
						tostring(ChallengeService.isBusy(player)),
						humanoid and tostring(humanoid.Health) or "-"
					)
				)
			end
		end
		if ChallengeService.isBusy(player) then
			pcall(ChallengeService.abort, player)
		end
		task.wait(3)
	end
end
