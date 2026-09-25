--!nocheck
--[[
	Примерочная аксессуаров каталога: манекен с аватаром игрока в каждой
	вещи-кандидате, по пять в ряд, снимки спереди и сзади. Так видно главное —
	как вещь сидит на настоящем персонаже, не прячется ли под волосами.

	ZZ_ONLY="id:тип,id:тип,…" — тип ассета каталога (8 шляпа, 42 лицо, 43 шея,
	44 плечи, 45 грудь, 46 спина, 47 пояс). Номера на снимке — порядок в списке.
	Кандидатов ищет python tools/models/catalog.py, запуск:
	ZZ_ONLY="607702162:8,12663134136:42" python tools/playtest/run.py tryon
]]
local Players = game:GetService("Players")

local FIELDS = {
	[8] = "HatAccessory",
	[41] = "HairAccessory",
	[42] = "FaceAccessory",
	[43] = "NeckAccessory",
	[44] = "ShouldersAccessory",
	[45] = "FrontAccessory",
	[46] = "BackAccessory",
	[47] = "WaistAccessory",
}
-- ZZ_RIDE=b — приставка к именам снимков, чтобы второй прогон не затёр первый.
local PREFIX = workspace:GetAttribute("ZZ_Ride") or ""
local PER_ROW = 3
local SPACING = 3.2

return function(player, note)
	for _ = 1, 60 do
		if player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(2)

	local ok, base = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not ok then
		base = player.Character.Humanoid:GetAppliedDescription()
	end
	-- Наши вещи и старые аксессуары аватара убираем, волосы оставляем: под ними и прячутся кепки.
	for _, field in FIELDS do
		if field ~= "HairAccessory" then
			base[field] = ""
		end
	end

	local list = {}
	for _, pair in string.split(workspace:GetAttribute("ZZ_Only") or "", ",") do
		local id, kind = string.match(pair, "^(%d+):(%d+)$")
		if id then
			table.insert(list, { id = id, kind = tonumber(kind) })
		end
	end
	note(`tryon {#list} items`)

	local stage = Instance.new("Part")
	stage.Anchored = true
	stage.Size = Vector3.new(PER_ROW * SPACING + 8, 1, 14)
	stage.Color = Color3.fromRGB(235, 230, 220)
	stage.Parent = workspace
	local origin = Vector3.new(0, 700, 0)
	stage.CFrame = CFrame.new(origin + Vector3.new((PER_ROW - 1) * SPACING / 2, -0.5, 0))

	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
		root.CFrame = CFrame.new(origin + Vector3.new(0, 3, 30))
	end

	for first = 1, #list, PER_ROW do
		local dummies = {}
		for slot = 0, PER_ROW - 1 do
			local entry = list[first + slot]
			if not entry then
				break
			end
			local desc = base:Clone()
			local field = FIELDS[entry.kind] or "HatAccessory"
			desc[field] = entry.id
			local made, model = pcall(function()
				return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			end)
			if not made then
				note(`#{first + slot} {entry.id}: FAILED {model}`)
				continue
			end
			model.Name = `Try_{entry.id}`
			model.Parent = workspace
			local hrp = model:FindFirstChild("HumanoidRootPart")
			hrp.Anchored = true
			local _, size = model:GetBoundingBox()
			model:PivotTo(CFrame.new(origin + Vector3.new(slot * SPACING, size.Y / 2, 0)))
			local count = 0
			for _, child in model:GetChildren() do
				if child:IsA("Accessory") then
					count += 1
				end
			end
			local tag = Instance.new("BillboardGui")
			tag.Size = UDim2.fromOffset(90, 30)
			tag.StudsOffsetWorldSpace = Vector3.new(0, -size.Y / 2 - 0.6, 0)
			tag.AlwaysOnTop = true
			tag.Adornee = hrp
			tag.Parent = hrp
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 0.3
			label.TextScaled = true
			label.Text = `#{first + slot - 1}`
			label.Parent = tag
			note(`#{first + slot - 1} {entry.id} accessories {count}`)
			table.insert(dummies, model)
		end
		task.wait(2.5) -- меши догружаются
		local mid = origin + Vector3.new((PER_ROW - 1) * SPACING / 2, 4.4, 0)
		local batch = math.floor((first - 1) / PER_ROW) + 1
		_G.ZZ_Shot(
			player,
			string.format("tryon%s_%02d_front", PREFIX, batch),
			CFrame.lookAt(mid + Vector3.new(0, 2.2, -8), mid),
			55
		)
		task.wait(4.2)
		_G.ZZ_Shot(
			player,
			string.format("tryon%s_%02d_back", PREFIX, batch),
			CFrame.lookAt(mid + Vector3.new(0, 2.2, 8), mid),
			55
		)
		task.wait(4.5)
		for _, model in dummies do
			model:Destroy()
		end
	end
end
