--!nocheck
--[[
	Азбука-дорожка: ребёнок проходит плитки от А до Я по порядку. Клиент
	должен зажигать пройденные (метка ZZ_Inspect — материал плиток), а после
	Я — пустить волну света. Снимки: общий вид и середина пути.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(22) -- зонд клиента слушает метки ZZ_* только через ~20 с после входа
	local root = player.Character.HumanoidRootPart
	local zone = workspace.Hub.Playground:FindFirstChild("Play_abcpath")
	if not zone then
		note("NO ABC PATH")
		return
	end
	local first = zone:FindFirstChild("Abc_1")
	local centre = Playground.position(Playground.expect("abcpath"))
	centre = Vector3.new(centre.X, first.Position.Y, centre.Z)
	local toPlaza = (-centre * Vector3.new(1, 0, 1)).Unit
	local view = CFrame.lookAt(centre + toPlaza * 24 + Vector3.new(0, 16, 0), centre)

	Teleport.to(player, CFrame.new(first.Position + Vector3.new(0, 4, 0)))
	for _ = 1, 40 do
		if not root.Anchored then
			break
		end
		task.wait(0.1)
	end
	task.wait(0.5)
	_G.ZZ_Shot(player, "abcpath", view, 60)

	for order = 1, 33 do
		local tile = zone:FindFirstChild(`Abc_{order}`)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(tile.Position + Vector3.new(0, 3.4, 0)) * root.CFrame.Rotation
		task.wait(0.55)
		if order == 17 then
			workspace:SetAttribute(
				"ZZ_Inspect",
				"Hub.Playground.Play_abcpath.Abc_1;Hub.Playground.Play_abcpath.Abc_17;Hub.Playground.Play_abcpath.Abc_18"
			)
			_G.ZZ_Shot(player, "abcpath_half", view, 60)
		end
	end
	task.wait(0.4)
	_G.ZZ_Shot(player, "abcpath_done", view, 60)
	workspace:SetAttribute("ZZ_Inspect", "Hub.Playground.Play_abcpath.Abc_33")
	task.wait(6)
	note("abcpath: walked А→Я")
end
