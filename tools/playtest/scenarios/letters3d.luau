--!nocheck
-- Объёмные буквы: секретная золотая буква в забеге и Азбучная арка на участке.
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local BaseService = require(Services.BaseService)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)

	pcall(BaseService.preview, 2, { house = 2, roof = 2, yard = 2, fence = 2 }, {
		arch = true,
		spire = true,
		flags = 3,
		mathFlags = 1,
		countSpire = false,
		letterRooms = {},
		mathRooms = {},
		stageFlags = {},
	})
	local plot = BaseService.plotCFrame(2)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = plot * CFrame.new(0, 5, -44)
	end
	task.wait(3)
	_G.ZZ_Shot(
		player,
		"arch_gate",
		CFrame.lookAt((plot * CFrame.new(2, 9, -46)).Position, (plot * CFrame.new(0, 9, -33.5)).Position),
		55
	)

	ChallengeService.startFor(player, "tunnel_run")
	task.wait(8)
	local tile
	for _, d in workspace:GetDescendants() do
		if string.sub(d.Name, 1, 10) == "SecretTile" and d:IsA("BasePart") then
			tile = d
			break
		end
	end
	note("secret tile " .. tostring(tile and tile.Position))
	if tile then
		root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local ahead = tile.CFrame * CFrame.new(0, 2, 14)
		if root then
			root.Anchored = true
			root.CFrame = ahead
		end
		task.wait(3)
		_G.ZZ_Shot(
			player,
			"secret_letter",
			CFrame.lookAt((tile.CFrame * CFrame.new(2, 1.5, 10)).Position, tile.Position),
			55
		)
		_G.ZZ_Shot(
			player,
			"secret_letter_2",
			CFrame.lookAt((tile.CFrame * CFrame.new(-4, 3, 7)).Position, tile.Position),
			55
		)
	end
end
