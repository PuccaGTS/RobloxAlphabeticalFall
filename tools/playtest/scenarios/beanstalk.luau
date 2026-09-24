--!nocheck
--[[
	Бобовый стебель (Config/Playground, beanstalk): вид с площади и снизу,
	сохранка в гнезде (сорвался выше гнезда — вернуло в гнездо), стручок-батут
	(подбрасывает выше обычного прыжка), остров с замком и сундук с «Облачком».
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Decor = require(ReplicatedStorage.Shared.Config.Decor)
	local Chests = require(ReplicatedStorage.Shared.Config.Chests)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(20) -- зонд клиента слушает метки не сразу

	local spot = Playground.expect("beanstalk")
	local p = Playground.position(spot)
	local ground = Decor.groundY(p.X, p.Z)
	local origin = CFrame.lookAt(Vector3.new(p.X, ground, p.Z), Vector3.new(0, ground, 0))
	local leaves = Playground.beanLeaves()
	local function leafTop(leaf)
		return (origin * CFrame.new(
			math.cos(leaf.angle) * leaf.radius,
			leaf.y,
			math.sin(leaf.angle) * leaf.radius
		)).Position
	end
	local function place(at)
		local root = player.Character.HumanoidRootPart
		Teleport.to(player, CFrame.new(at + Vector3.new(0, 3.5, 0)))
		for _ = 1, 40 do
			if not root.Anchored then
				break
			end
			task.wait(0.1)
		end
		task.wait(0.2)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(at + Vector3.new(0, 3.2, 0))
		return root
	end

	-- С площади: остров над парком видно издалека.
	local top = origin.Position + Vector3.new(0, Playground.BEAN_TOP, 0)
	_G.ZZ_Shot(
		player,
		"bean_from_plaza",
		CFrame.lookAt(Vector3.new(0, 12, 0), top + Vector3.new(0, -12, 0)),
		60
	)
	_G.ZZ_Shot(
		player,
		"bean_whole",
		CFrame.lookAt((origin * CFrame.new(0, 28, -62)).Position, origin.Position + Vector3.new(0, 30, 0)),
		70
	)
	_G.ZZ_Shot(
		player,
		"bean_base",
		CFrame.lookAt((origin * CFrame.new(6, 8, -20)).Position, origin.Position + Vector3.new(0, 10, 0)),
		70
	)

	-- Сохранка: встал в гнездо, поднялся выше и сорвался.
	local nest, above
	for index, leaf in leaves do
		if leaf.kind == "nest" then
			nest = leaf
			above = leaves[index + 3]
		end
	end
	local root = place(leafTop(nest))
	task.wait(1.5)
	_G.ZZ_Shot(
		player,
		"bean_nest",
		CFrame.lookAt(root.Position + (origin.LookVector * -10) + Vector3.new(4, 5, 0), root.Position),
		60
	)
	place(leafTop(above))
	task.wait(1)
	-- Шаг в пустоту наружу от стебля: падение до земли.
	local out = (leafTop(above) - origin.Position) * Vector3.new(1, 0, 1)
	root.CFrame = CFrame.new(leafTop(above) + out.Unit * 6 + Vector3.new(0, 3, 0))
	local lowest = root.Position.Y
	for _ = 1, 30 do
		task.wait(0.1)
		lowest = math.min(lowest, root.Position.Y)
	end
	task.wait(1)
	note(
		string.format(
			"nest y %.1f, fell from y %.1f to lowest %.1f, now y %.1f (ground %.1f), distance to nest %.1f",
			nest.y,
			above.y,
			lowest - ground,
			root.Position.Y - ground,
			0,
			(root.Position - leafTop(nest)).Magnitude
		)
	)

	-- Стручок-батут: упасть на него сверху и мерить высоту.
	for index, leaf in leaves do
		if leaf.kind == "pod" then
			-- Сначала переносим рядом, потом включаем замер на клиенте и роняем на стручок.
			place(leafTop(leaf) + Vector3.new(0, 0.5, 2))
			task.wait(1)
			workspace:SetAttribute("ZZ_Peak", 4)
			task.wait(0.5)
			local r = player.Character.HumanoidRootPart
			r.AssemblyLinearVelocity = Vector3.zero
			r.CFrame = CFrame.new(leafTop(leaf) + Vector3.new(0, 6, 0))
			local peak = r.Position.Y
			for _ = 1, 30 do
				task.wait(0.05)
				peak = math.max(peak, r.Position.Y)
			end
			note(
				string.format(
					"pod at y %.1f: root peak %.1f above pod top, next leaf %.1f higher",
					leaf.y,
					peak - leafTop(leaf).Y - 3,
					leaves[index + 1].y - leaf.y
				)
			)
		end
	end

	-- Остров: ура, замок, гусыня. Потом сундук — касанием, как ребёнок.
	place(top + (origin.LookVector * 9))
	task.wait(2)
	_G.ZZ_Shot(
		player,
		"bean_island",
		CFrame.lookAt(top + origin.LookVector * 22 + Vector3.new(6, 9, 0), top + Vector3.new(0, 3, 4)),
		70
	)
	local chest = Chests.get("chest_sky")
	local at = Chests.position(chest) + Vector3.new(0, ground + chest.height, 0)
	place(at + origin.LookVector * 2.2)
	task.wait(3)
	local profile = ProfileService.get(player)
	note(`chest_sky opened: {table.find(profile.inventory, chest.itemId) ~= nil}, hat {profile.equipped.hat}`)
	local r = player.Character.HumanoidRootPart
	_G.ZZ_Shot(
		player,
		"bean_hat",
		CFrame.lookAt(
			r.Position + r.CFrame.LookVector * 7 + Vector3.new(2, 2, 0),
			r.Position + Vector3.new(0, 1.5, 0)
		),
		60
	)
end
