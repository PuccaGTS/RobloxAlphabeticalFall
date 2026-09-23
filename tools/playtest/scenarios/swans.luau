--!nocheck
--[[
	Озеро с лодочками-лебедями: общий вид, посадка с мостков — сервер смотрит,
	сидит ли ребёнок и плывёт ли он по кругу озера.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Rides = require(ReplicatedStorage.Shared.Config.Rides)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(8)
	local root = player.Character.HumanoidRootPart
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local lake = Playground.position(Playground.expect("lake"))
	local zone = workspace.Hub.Playground:FindFirstChild("Play_lake")
	local pad = zone and zone:FindFirstChild("BoardPad")
	if not pad then
		note("NO LAKE")
		return
	end
	-- Подойти по берегу, чтобы стриминг отдал озеро, и снять общий вид.
	local outward = (lake * Vector3.new(1, 0, 1)).Unit
	Teleport.to(player, CFrame.new(lake - outward * 34 + Vector3.new(0, 4, 0)))
	task.wait(3)
	_G.ZZ_Shot(
		player,
		"swans_lake",
		CFrame.lookAt(lake - outward * 36 + Vector3.new(8, 14, 0), lake + Vector3.new(0, 2, 0)),
		60
	)

	Teleport.to(player, CFrame.new(pad.Position + Vector3.new(0, 3, 0)))
	task.wait(3)
	local start = root.Position
	note(
		string.format(
			"swans: sit=%s, root from lake centre %.1f (loop %d)",
			tostring(humanoid.Sit),
			((root.Position - lake) * Vector3.new(1, 0, 1)).Magnitude,
			Rides.SWANS.loop
		)
	)
	task.wait(1)
	_G.ZZ_Shot(
		player,
		"swans_ride",
		CFrame.lookAt(root.Position + Vector3.new(0, 7, 0) + (root.Position - lake).Unit * 12, root.Position),
		60
	)
	task.wait(3)
	note(
		string.format(
			"swans: moved %.1f studs, sit=%s, from centre %.1f",
			(root.Position - start).Magnitude,
			tostring(humanoid.Sit),
			((root.Position - lake) * Vector3.new(1, 0, 1)).Magnitude
		)
	)
end
