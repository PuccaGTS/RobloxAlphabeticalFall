--!nocheck
--[[
	Витрина импортированных моделей: каждая на своей платформе высоко в небе,
	в натуральную величину, рядом человечек ребёнка для масштаба. Снимок на модель.
	workspace:GetAttribute("ZZ_Only") — через запятую, если нужны не все.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(player, note)
	task.wait(3)
	local folder = ReplicatedStorage.Assets.decor
	local only = workspace:GetAttribute("ZZ_Only")
	local models = {}
	for _, model in folder:GetChildren() do
		if not only or table.find(string.split(only, ","), model.Name) then
			table.insert(models, model)
		end
	end
	table.sort(models, function(a, b)
		return a.Name < b.Name
	end)
	local base = Vector3.new(0, 600, 0)
	local stage = Instance.new("Part")
	stage.Anchored = true
	stage.Size = Vector3.new(80, 2, 80)
	stage.Color = Color3.fromRGB(120, 180, 110)
	stage.Material = Enum.Material.Grass
	stage.Parent = workspace
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	for _, template in models do
		stage.CFrame = CFrame.new(base - Vector3.new(0, 1, 0))
		local model = template:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		model.Parent = workspace
		local box, size = model:GetBoundingBox()
		model:PivotTo(model:GetPivot() + (base - Vector3.new(box.Position.X, box.Position.Y - size.Y / 2, box.Position.Z)))
		if root then
			root.Anchored = true
			root.CFrame = CFrame.new(base + Vector3.new(size.X / 2 + 4, 3, 0))
		end
		local reach = math.max(size.X, size.Y, size.Z, 8)
		local eye = base + Vector3.new(reach * 0.9, reach * 0.6, reach * 1.4)
		note(string.format("%s size %.1f x %.1f x %.1f", template.Name, size.X, size.Y, size.Z))
		_G.ZZ_Shot(player, "show_" .. template.Name, CFrame.lookAt(eye, base + Vector3.new(0, size.Y * 0.4, 0)), 60)
		model:Destroy()
	end
end
