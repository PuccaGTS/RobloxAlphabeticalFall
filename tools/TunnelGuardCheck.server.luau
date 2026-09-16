--!nocheck
--[[
	Проверка невидимых стенок туннеля: нет ли щелей, в которые можно выпасть
	с трассы, и не залезает ли стенка на дорожки.

	Собирает восемь забегов 11-го уровня на фиксированных сидах и через каждые
	два студа пускает лучи от середины трассы влево и вправо на трёх высотах.
	Итог: у каждого сида gaps 0 и intrusions 0.

	  rojo build default.project.json -o build/game.rbxl
	  run-in-roblox --place build/game.rbxl --script tools/TunnelGuardCheck.server.luau

	Не юнит-тест: туннель строится сервисами с путями боевого места, а тестовое
	место раскладывает их иначе.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = ServerScriptService:WaitForChild("Server")
require(ReplicatedStorage.Shared.Net.RemoteDefs).init()
local TunnelService = require(Server.Services.TunnelService)
local TunnelRun = require(Server.Challenges.TunnelRun)
local TrackShape = require(ReplicatedStorage.Shared.Logic.TrackShape)
local Tunnel = require(ReplicatedStorage.Shared.Config.Tunnel)
local fake = { UserId = 1, Name = "Smoke", DisplayName = "Smoke", Character = nil }

local out = {}
local totalParts, totalGaps = 0, 0
for seed = 1, 8 do
	local ok, err = pcall(function()
		local spec = TunnelRun.Rebuild({ letters = { "a", "b", "v" }, difficulty = 5, seed = seed * 7919, checkpoint = 0, level = 11 })
		TunnelService.spawn(fake, spec)
		local model = workspace.Tunnels:FindFirstChildWhichIsA("Model")
		local guards, parts = {}, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d.Name:match("^Guard") then
					table.insert(guards, d)
				end
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = guards
		local sampler = TrackShape.sampler(spec.params.track, spec.params.length)
		local index = math.floor((guards[1].Position.X - Tunnel.PLOT_ORIGIN.X) / Tunnel.PLOT_SPACING + 0.5)
		local base = CFrame.new(Tunnel.PLOT_ORIGIN + Vector3.new(index * Tunnel.PLOT_SPACING, 0, 0))
		local gaps = 0
		local intrusions, worst = 0, math.huge
		local z = 1
		while z < spec.params.length - 1 do
			local at = base * sampler.flat(z)
			for _, side in { -1, 1 } do
				for _, h in { 1, 3, 6 } do
					local from = (at * CFrame.new(0, h, 0)).Position
					local to = (at * CFrame.new(side * (Tunnel.WIDTH / 2 + Tunnel.WALL_THICKNESS + 1), h, 0)).Position
					local hit = workspace:Raycast(from, to - from, params)
					if hit and hit.Distance < Tunnel.WIDTH / 2 - 0.3 then
						intrusions += 1
						worst = math.min(worst, hit.Distance)
					end
					if not hit then
						gaps += 1
						if gaps <= 3 then
							local zone = sampler.zoneAt(z)
							table.insert(out, string.format("  gap seed %d z=%.0f side %d h %d zone %s", seed, z, side, h, zone and zone.kind or "-"))
						end
					end
				end
			end
			z += 2
		end
		table.insert(out, string.format("seed %d parts %d guards %d gaps %d intrusions %d closest %.2f (half %.1f)", seed, parts, #guards, gaps, intrusions, worst, Tunnel.WIDTH / 2))
		totalParts += parts
		totalGaps += gaps
		TunnelService.despawn(fake)
	end)
	if not ok then
		table.insert(out, "FAIL " .. tostring(err))
	end
end
table.insert(out, string.format("TOTAL parts %d gaps %d", totalParts, totalGaps))
print("GC-BEGIN")
for _, line in out do
	print(line)
end
print("GC-END")
