--!nocheck
-- Замер производительности: что стоит в мире и сколько стоит кадр в характерных местах.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

local remote = Instance.new("RemoteFunction")
remote.Name = "ZZ_Perf"
remote.Parent = ReplicatedStorage

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local BaseService = require(Services.BaseService)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(6)

	-- Худший случай для площади: все двадцать участков застроены до конца.
	for index = 2, 20 do
		pcall(BaseService.preview, index, { house = 4, roof = 4, yard = 4, fence = 4, furniture = 4, decor = 4, garden = 4, playground = 4, pets = 4, transport = 4 })
	end
	task.wait(2)

	-- Сервер: всё, что есть в мире, по разделам верхнего уровня.
	local rows = {}
	for _, child in workspace:GetChildren() do
		local parts, shadows, lights, emitters, guis = 0, 0, 0, 0, 0
		for _, d in child:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d.CastShadow then
					shadows += 1
				end
			elseif d:IsA("Light") then
				lights += 1
			elseif d:IsA("ParticleEmitter") then
				emitters += 1
			elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
				guis += 1
			end
		end
		if parts > 50 then
			table.insert(rows, { child.Name, parts, shadows, lights, emitters, guis })
		end
	end
	table.sort(rows, function(a, b)
		return a[2] > b[2]
	end)
	for _, row in rows do
		note(string.format("WORLD %-28s parts=%5d shadow=%5d lights=%3d emitters=%3d guis=%4d", row[1], row[2], row[3], row[4], row[5], row[6]))
	end

	-- Кто тяжелее всех: детали по видам (имя без номера) внутри площади и одного участка.
	local function breakdown(root, label)
		local kinds = {}
		for _, child in root:GetDescendants() do
			if child:IsA("Model") and child.Parent and (child.Parent == root or child.Parent.Parent == root) then
				local kind = string.gsub(child.Name, "_%d+$", "")
				local count = 0
				for _, d in child:GetDescendants() do
					if d:IsA("BasePart") then
						count += 1
					end
				end
				local entry = kinds[kind] or { n = 0, parts = 0, tris = 0 }
				entry.n += 1
				entry.parts += count
				kinds[kind] = entry
			end
		end
		local list = {}
		for kind, entry in kinds do
			table.insert(list, { kind, entry })
		end
		table.sort(list, function(a, b)
			return a[2].parts > b[2].parts
		end)
		for i = 1, math.min(14, #list) do
			note(string.format("KIND %s %-28s x%-3d parts=%d", label, list[i][1], list[i][2].n, list[i][2].parts))
		end
	end
	breakdown(workspace.Hub, "hub")
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		local one = plots:GetChildren()[3]
		local counts = {}
		for _, d in one:GetDescendants() do
			if d:IsA("BasePart") then
				local kind = string.gsub(string.gsub(d.Name, "_[%-%d%.]+", ""), "%d+$", "")
				counts[kind] = (counts[kind] or 0) + 1
			end
		end
		local list = {}
		for kind, n in counts do
			table.insert(list, { kind, n })
		end
		table.sort(list, function(a, b)
			return a[2] > b[2]
		end)
		local text = {}
		for i = 1, math.min(25, #list) do
			table.insert(text, `{list[i][1]}={list[i][2]}`)
		end
		note(`PLOT {one.Name}: {table.concat(text, " ")}`)
	end

	local plaza = BaseService.plotCFrame(2)
	local views = {
		{ "spawn", CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 8, -20)) },
		{ "plaza_high", CFrame.lookAt(Vector3.new(60, 80, 120), Vector3.new(0, 0, -20)) },
		{ "park", CFrame.lookAt(Vector3.new(-40, 10, 60), Vector3.new(-90, 5, 140)) },
		{ "yards", CFrame.lookAt((plaza * CFrame.new(20, 18, -60)).Position, plaza.Position) },
	}
	if workspace:GetAttribute("ZZ_Only") == "world" then
		return
	end
	if workspace:GetAttribute("ZZ_Only") == "tris" then
		local view = CFrame.lookAt(Vector3.new(60, 80, 120), Vector3.new(0, 0, -20))
		-- Первый замер дважды: пока мир догружается, число треугольников растёт само.
		local kinds = { false, false, "Plots", false, "HubBalls", false, "HubMeshes", false, "PlotCylinders", false }
		local balls, cylinders, parts = 0, 0, 0
		for _, d in workspace.Plots:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d:IsA("Part") and d.Shape == Enum.PartType.Ball then
					balls += 1
				elseif d:IsA("Part") and d.Shape == Enum.PartType.Cylinder then
					cylinders += 1
				end
			end
		end
		note(`PLOTS parts={parts} balls={balls} cylinders={cylinders}`)
		local hubBalls, hubMeshes = 0, 0
		for _, d in workspace.Hub:GetDescendants() do
			if d:IsA("Part") and d.Shape == Enum.PartType.Ball then
				hubBalls += 1
			end
			if d:IsA("BasePart") and d:FindFirstChildOfClass("SpecialMesh") then
				hubMeshes += 1
			end
		end
		note(`HUB balls={hubBalls} meshes={hubMeshes}`)
		for _, kind in kinds do
			local ok, result = pcall(function()
				return remote:InvokeClient(player, view, kind or nil)
			end)
			local tris = if ok then string.match(result, "tris=(%d+)") else "?"
			local parts = if ok then string.match(result, "nearShadow=(%d+)") else "?"
			note(`TRIS without {kind or "nothing"}: tris={tris}`)
		end
		return
	end
	for _, view in views do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.new(view[2].Position + Vector3.new(0, 2, 0))
			root.Anchored = true
		end
		local ok, result = pcall(function()
			return remote:InvokeClient(player, view[2])
		end)
		note(`VIEW {view[1]}: {if ok then result else "FAIL " .. tostring(result)}`)
	end
end
