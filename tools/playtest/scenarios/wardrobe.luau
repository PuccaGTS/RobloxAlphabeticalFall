--!nocheck
--[[
	Гардероб глазами ребёнка: игрок по очереди надевает вещи магазина,
	снимок лица и спины на каждую. ZZ_ONLY="hat_cap,face_glasses" — какие вещи;
	без него — все шапки, лица и спины по цене.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local CosmeticsService = require(Services.CosmeticsService)
	local Shop = require(ReplicatedStorage.Shared.Config.Shop)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(4)

	local ids = {}
	local only = workspace:GetAttribute("ZZ_Only")
	if only then
		ids = string.split(only, ",")
	else
		for _, id in Shop.ids() do
			local item = Shop.expect(id)
			if item.category == "hat" or item.category == "face" or item.category == "back" then
				table.insert(ids, id)
			end
		end
	end

	local stage = Instance.new("Part")
	stage.Anchored = true
	stage.Size = Vector3.new(20, 1, 20)
	stage.Color = Color3.fromRGB(235, 230, 220)
	stage.CFrame = CFrame.new(0, 699.5, 0)
	stage.Parent = workspace
	local root = player.Character.HumanoidRootPart
	root.Anchored = true
	root.CFrame = CFrame.new(0, 703, 0)

	for index, id in ids do
		local item = Shop.get(id)
		if not item then
			note(`{id}: NO ITEM`)
			continue
		end
		ProfileService.update(player, function(p)
			p.equipped = { pets = p.equipped.pets }
			p.equipped[item.category] = id
		end)
		CosmeticsService.apply(player)
		task.wait(2)
		local head = player.Character.Head.Position
		local look = if item.category == "back" then Vector3.new(4, 1.5, 6) else Vector3.new(2.5, 1.2, -5.5)
		local aim = if item.category == "back" then head - Vector3.new(0, 1.2, 0) else head
		_G.ZZ_Shot(player, string.format("ward_%02d_%s", index, id), CFrame.lookAt(head + look, aim), 50)
		note(`{index} {id} {item.title} {if item.accessory then "accessory" else "parts"}`)
		task.wait(4.3)
	end
end
