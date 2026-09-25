--!nocheck
--[[
	Смотрины буквят: модели Assets.pets (или кандидаты из Assets.decor с префиксом
	ZZ_Only, «petc_<вид>_<номер>»), каждая сжата до размера буквёнка, в ряд по виду,
	подписаны. Снимки на ряд: со стороны −Z (перёд модели по правилам Roblox) и сбоку.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(player, note)
	task.wait(12) -- раньше клиент не готов, и первый снимок выходит с площади
	game:GetService("Lighting").ClockTime = 13
	local prefix = workspace:GetAttribute("ZZ_Only")
	local rows = {}
	if prefix and string.find(prefix, ",") then
		-- Список имён моделей декора через запятую — один ряд.
		rows.list = {}
		for _, name in string.split(prefix, ",") do
			table.insert(rows.list, ReplicatedStorage.Assets.decor[name])
		end
		prefix = ""
	elseif prefix then
		for _, model in ReplicatedStorage.Assets.decor:GetChildren() do
			if string.sub(model.Name, 1, #prefix) == prefix then
				local kind = string.split(string.sub(model.Name, #prefix + 1), "_")[1]
				rows[kind] = rows[kind] or {}
				table.insert(rows[kind], model)
			end
		end
	else
		prefix = ""
		rows.pets = ReplicatedStorage.Assets.pets:GetChildren()
	end
	local base = Vector3.new(0, 600, 0)
	local stage = Instance.new("Part")
	stage.Anchored = true
	stage.Size = Vector3.new(60, 2, 20)
	stage.Color = Color3.fromRGB(120, 180, 110)
	stage.Material = Enum.Material.Grass
	stage.CFrame = CFrame.new(base - Vector3.new(0, 1, 0))
	stage.Parent = workspace
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
		root.CFrame = CFrame.new(base + Vector3.new(-14, 3, 0))
	end
	for kind, list in rows do
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
		local shown = {}
		for index, template in list do
			local model = template:Clone()
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
				end
			end
			model.Parent = workspace
			local _, size = model:GetBoundingBox()
			model:ScaleTo(model:GetScale() * 3 / math.max(size.X, size.Y, size.Z))
			local box, scaled = model:GetBoundingBox()
			local spot = base + Vector3.new((index - 1) * 4.2 - 10, 0, 0)
			model:PivotTo(
				model:GetPivot()
					+ (spot - Vector3.new(box.Position.X, box.Position.Y - scaled.Y / 2, box.Position.Z))
			)
			local tag = Instance.new("BillboardGui")
			tag.Size = UDim2.fromOffset(160, 30)
			tag.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
			tag.AlwaysOnTop = true
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Text = string.sub(template.Name, #prefix + 1)
			label.Parent = tag
			tag.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			tag.Parent = model
			note(string.format("%s parts %d", template.Name, #model:GetDescendants()))
			table.insert(shown, model)
		end
		_G.ZZ_Shot(
			player,
			"pets_" .. kind .. "_front",
			CFrame.lookAt(base + Vector3.new(4, 5, -16), base + Vector3.new(4, 1.5, 0)),
			60
		)
		task.wait(6)
		_G.ZZ_Shot(
			player,
			"pets_" .. kind .. "_top",
			CFrame.lookAt(base + Vector3.new(4, 22, 0.01), base + Vector3.new(4, 0, 0)),
			60
		)
		task.wait(6)
		for _, model in shown do
			model:Destroy()
		end
	end
end
