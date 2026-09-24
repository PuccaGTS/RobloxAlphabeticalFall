--!nocheck
-- Клиентская половина зонда: что видит ребёнок. Отчёт уходит серверному зонду.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local report = ReplicatedStorage:WaitForChild("ZZ_ProbeReport")
local player = Players.LocalPlayer
-- Ошибки клиента — в отчёт: без этого упавший каждый кадр контроллер виден только по снимкам.
do
	local seen = {}
	game:GetService("LogService").MessageOut:Connect(function(message, kind)
		if kind == Enum.MessageType.MessageError and not seen[message] then
			seen[message] = true
			report:FireServer("CLIENT ERROR " .. message)
		end
	end)
end
-- Замер производительности по просьбе сценария perf: камера в точку, три секунды кадров, счётчики отрисовки.
local perf = if workspace:GetAttribute("ZZ_Perf") then ReplicatedStorage:WaitForChild("ZZ_Perf", 30) else nil
if perf then
	perf.OnClientInvoke = function(cframe, hideKind)
		-- hideKind: спрятать детали предметов этого вида (имя модели без номера) и мерить без них.
		if hideKind then
			for _, d in workspace:GetDescendants() do
				if
					d:IsA("Model") and (string.gsub(d.Name, "_%d+$", "") == hideKind or d.Name == hideKind)
				then
					for _, piece in d:GetDescendants() do
						if piece:IsA("BasePart") then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				elseif hideKind == "HubBalls" and (d.Name == "Hub" or d.Name == "Venues") then
					for _, piece in d:GetDescendants() do
						if piece:IsA("Part") and piece.Shape == Enum.PartType.Ball then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				elseif hideKind == "HubMeshes" and d.Name == "Hub" then
					for _, piece in d:GetDescendants() do
						if
							piece:IsA("BasePart")
							and (piece:FindFirstChildOfClass("SpecialMesh") or piece:IsA("MeshPart"))
						then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				elseif
					(hideKind == "PlotBalls" or hideKind == "PlotCylinders" or hideKind == "PlotWedges")
					and d.Name == "Plots"
				then
					local shape = if hideKind == "PlotBalls"
						then Enum.PartType.Ball
						else Enum.PartType.Cylinder
					for _, piece in d:GetDescendants() do
						local match = if hideKind == "PlotWedges"
							then piece:IsA("WedgePart")
							else piece:IsA("Part") and piece.Shape == shape
						if match then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				elseif hideKind == "Plots" and d.Name == "Plots" then
					for _, piece in d:GetDescendants() do
						if piece:IsA("BasePart") then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				end
			end
		end
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cframe
		pcall(function()
			player:RequestStreamAroundAsync(cframe.Position, 5)
		end)
		task.wait(4)
		local RunService = game:GetService("RunService")
		local frames, total, worst = 0, 0, 0
		local connection = RunService.RenderStepped:Connect(function(dt)
			frames += 1
			total += dt
			worst = math.max(worst, dt)
		end)
		task.wait(3)
		connection:Disconnect()
		local Stats = game:GetService("Stats")
		local function stat(name)
			local ok, value = pcall(function()
				return Stats[name]
			end)
			return if ok then tostring(value) else "?"
		end
		local parts, near, shadows, lights, emitters, billboards, surfaces = 0, 0, 0, 0, 0, 0, 0
		local position = cframe.Position
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if (d.Position - position).Magnitude < 250 then
					near += 1
					if d.CastShadow and d.Transparency < 1 then
						shadows += 1
					end
				end
			elseif d:IsA("Light") and d.Enabled then
				lights += 1
			elseif d:IsA("ParticleEmitter") and d.Enabled then
				emitters += 1
			elseif d:IsA("BillboardGui") and d.Enabled then
				billboards += 1
			elseif d:IsA("SurfaceGui") and d.Enabled then
				surfaces += 1
			end
		end
		camera.CameraType = Enum.CameraType.Custom
		for _, d in workspace:GetDescendants() do
			if d:GetAttribute("ZZ_Hidden") then
				d.LocalTransparencyModifier = 0
				d:SetAttribute("ZZ_Hidden", nil)
			end
		end
		return string.format(
			"fps=%.0f worst=%.0fms parts=%d near250=%d nearShadow=%d lights=%d emitters=%d billboards=%d surfaceGuis=%d draw=%s tris=%s shadowDraw=%s mem=%s",
			frames / total,
			worst * 1000,
			parts,
			near,
			shadows,
			lights,
			emitters,
			billboards,
			surfaces,
			stat("SceneDrawcallCount"),
			stat("SceneTriangleCount"),
			stat("ShadowsDrawcallCount"),
			tostring(math.floor(Stats:GetTotalMemoryUsageMb()))
		)
	end
end

-- Сценарий зовёт радугу меткой в Workspace: у сервера до клиентского контроллера не дотянуться.
workspace:GetAttributeChangedSignal("ZZ_Rainbow"):Connect(function()
	local scripts = player:WaitForChild("PlayerScripts")
	require(scripts.Client.Controllers.LiveWorldController).rainbow(120)
end)
task.wait(6)
local gui = player:WaitForChild("PlayerGui")
local names = {}
for _, child in gui:GetChildren() do
	table.insert(names, child.Name)
end
report:FireServer("PlayerGui: " .. table.concat(names, ", "))
report:FireServer("DevTools attr = " .. tostring(player:GetAttribute("DevTools")))
-- Где кнопки в углу: панель разработчика и родительский режим.
task.wait(2)
for _, screen in gui:GetChildren() do
	if screen:IsA("ScreenGui") then
		for _, button in screen:GetDescendants() do
			if
				workspace:GetAttribute("ZZ_Buttons")
				and button:IsA("GuiButton")
				and button.AbsoluteSize.X > 0
				and button.AbsolutePosition.X < 200
			then
				local shown = button.Visible and screen.Enabled
				local cursor = button.Parent
				while shown and cursor and cursor ~= screen do
					if cursor:IsA("GuiObject") and not cursor.Visible then
						shown = false
					end
					cursor = cursor.Parent
				end
				local text = if button:IsA("TextButton") then button.Text else "img"
				report:FireServer(
					string.format(
						"BUTTON %s.%s '%s' at %s size %s shown=%s order=%d",
						screen.Name,
						button.Name,
						text,
						tostring(button.AbsolutePosition),
						tostring(button.AbsoluteSize),
						tostring(shown),
						screen.DisplayOrder
					)
				)
			end
		end
	end
end

task.delay(12, function()
	local loaded, empty, sample = 0, 0, ""
	for _, d in workspace:GetDescendants() do
		if d:IsA("MeshPart") then
			if d.MeshSize.Magnitude > 0 then
				loaded += 1
				if sample == "" then
					sample = d:GetFullName()
						.. " MeshSize "
						.. tostring(d.MeshSize)
						.. " Size "
						.. tostring(d.Size)
				end
			else
				empty += 1
			end
		end
	end
	report:FireServer(string.format("MESHES loaded=%d empty=%d sample=%s", loaded, empty, sample))
	local ContentProvider = game:GetService("ContentProvider")
	local statuses = {}
	local seen = {}
	for _, d in workspace:GetDescendants() do
		if
			d:IsA("SpecialMesh")
			and d.MeshType == Enum.MeshType.FileMesh
			and d.MeshId ~= ""
			and not seen[d.MeshId]
		then
			seen[d.MeshId] = true
			ContentProvider:PreloadAsync({ d })
			local status = ContentProvider:GetAssetFetchStatus(d.MeshId)
			statuses[status.Name] = (statuses[status.Name] or 0) + 1
		end
	end
	local parts = {}
	for name, count in statuses do
		table.insert(parts, name .. "=" .. count)
	end
	report:FireServer("FILEMESH fetch: " .. table.concat(parts, " "))
end)

-- Звуки по просьбе сценария (метка ZZ_AudioReport): что играет, загрузилось ли, сколько длится.
workspace:GetAttributeChangedSignal("ZZ_AudioReport"):Connect(function()
	local lines = {}
	local SoundService = game:GetService("SoundService")
	for _, root in { SoundService, workspace } do
		for _, d in root:GetDescendants() do
			if d:IsA("Sound") and d.SoundId ~= "" and not d.SoundId:find("^rbxasset://") then
				table.insert(
					lines,
					string.format(
						"%s[%s] loaded=%s len=%.0f playing=%s vol=%.2f",
						d.Name,
						d.SoundId:match("%d+") or "?",
						tostring(d.IsLoaded),
						d.TimeLength,
						tostring(d.IsPlaying),
						d.Volume
					)
				)
			end
		end
	end
	report:FireServer(
		"AUDIO " .. workspace:GetAttribute("ZZ_AudioReport") .. ": " .. table.concat(lines, " | ")
	)
end)

-- Деталь глазами клиента (метка ZZ_Inspect = "Hub.Playground.…"): где стоит, что в ней излучает.
workspace:GetAttributeChangedSignal("ZZ_Inspect"):Connect(function()
	for path in string.gmatch(workspace:GetAttribute("ZZ_Inspect") or "", "[^;]+") do
		local node = workspace
		for name in string.gmatch(path, "[^%.]+") do
			node = node and node:FindFirstChild(name)
		end
		if not node then
			report:FireServer("INSPECT " .. path .. ": нет у клиента")
			continue
		end
		local lines = { node.ClassName }
		if node:IsA("BasePart") then
			table.insert(
				lines,
				string.format(
					"pos %.1f,%.1f,%.1f rot %s",
					node.Position.X,
					node.Position.Y,
					node.Position.Z,
					tostring(node.Orientation)
				)
			)
		end
		for _, child in node:GetChildren() do
			if child:IsA("ParticleEmitter") then
				table.insert(
					lines,
					string.format("emitter rate=%.0f enabled=%s", child.Rate, tostring(child.Enabled))
				)
			elseif child:IsA("Sound") then
				table.insert(
					lines,
					string.format("sound playing=%s vol=%.2f", tostring(child.IsPlaying), child.Volume)
				)
			end
		end
		report:FireServer("INSPECT " .. path .. ": " .. table.concat(lines, " | "))
	end
end)

-- Загрузка звуков библиотеки (метка ZZ_SoundCheck = "ключ,ключ"): грузится ли и сколько длится.
workspace:GetAttributeChangedSignal("ZZ_SoundCheck"):Connect(function()
	local AudioRegistry = require(game:GetService("ReplicatedStorage").Shared.Config.AudioRegistry)
	local sounds = {}
	for key in string.gmatch(workspace:GetAttribute("ZZ_SoundCheck") or "", "[^,]+") do
		local sound = Instance.new("Sound")
		sound.Name = key
		sound.SoundId = AudioRegistry.ids[key] or ""
		sound.Parent = game:GetService("SoundService")
		table.insert(sounds, sound)
	end
	local started = os.clock()
	while os.clock() - started < 12 do
		local all = true
		for _, sound in sounds do
			all = all and sound.IsLoaded
		end
		if all then
			break
		end
		task.wait(0.25)
	end
	local lines = {}
	for _, sound in sounds do
		table.insert(
			lines,
			string.format("%s loaded=%s len=%.1f", sound.Name, tostring(sound.IsLoaded), sound.TimeLength)
		)
		sound:Destroy()
	end
	report:FireServer("SOUNDS " .. table.concat(lines, " | "))
end)

--[[
	Пройтись по просьбе сценария (метка ZZ_Walk = "x,z,секунды"): с сервера клиентского
	персонажа не сдвинуть, а тут он идёт как от джойстика. Докладывает путь, скорость
	и какие анимации играли — так проверяется прокат и всё, что меняет походку.
]]
workspace:GetAttributeChangedSignal("ZZ_Walk"):Connect(function()
	local spec = workspace:GetAttribute("ZZ_Walk")
	if typeof(spec) ~= "string" then
		return
	end
	local x, z, seconds = string.match(spec, "([%-%d%.]+),([%-%d%.]+),([%d%.]+)")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not x then
		report:FireServer("WALK: нет персонажа или метка без чисел")
		return
	end
	local direction = Vector3.new(tonumber(x), 0, tonumber(z)).Unit
	-- Стандартное управление каждый кадр зовёт Move с нулём — на время прогулки его выключаем.
	local controls = nil
	pcall(function()
		controls = require(player.PlayerScripts:WaitForChild("PlayerModule")):GetControls()
		controls:Disable()
	end)
	local start = root.Position
	local deadline = os.clock() + tonumber(seconds)
	local fastest = 0
	while os.clock() < deadline do
		humanoid:Move(direction, false)
		local v = root.AssemblyLinearVelocity
		fastest = math.max(fastest, Vector3.new(v.X, 0, v.Z).Magnitude)
		task.wait()
	end
	humanoid:Move(Vector3.zero, false)
	if controls then
		controls:Enable()
	end
	local tracks = {}
	for _, t in humanoid:FindFirstChildOfClass("Animator"):GetPlayingAnimationTracks() do
		table.insert(
			tracks,
			`{t.Animation and t.Animation.AnimationId:match("%d+") or "?"}:{t.Priority.Name}`
		)
	end
	report:FireServer(
		string.format(
			"WALK %.1f studs in %ss, top speed %.1f, walkspeed %.0f hip %.2f, tracks %s",
			((root.Position - start) * Vector3.new(1, 0, 1)).Magnitude,
			seconds,
			fastest,
			humanoid.WalkSpeed,
			humanoid.HipHeight,
			table.concat(tracks, " ")
		)
	)
end)

-- Высшая точка корня глазами клиента (метка ZZ_Peak = секунды): сервер её занижает.
workspace:GetAttributeChangedSignal("ZZ_Peak"):Connect(function()
	local seconds = workspace:GetAttribute("ZZ_Peak")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if typeof(seconds) ~= "number" or not root then
		return
	end
	local start = root.Position.Y
	local peak = start
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		peak = math.max(peak, root.Position.Y)
		task.wait()
	end
	report:FireServer(string.format("PEAK start y %.1f, peak y %.1f (+%.1f)", start, peak, peak - start))
end)

-- Танец по просьбе сценария (метка ZZ_Emote): открыть ряд жестов, станцевать, доложить дорожки.
workspace:GetAttributeChangedSignal("ZZ_Emote"):Connect(function()
	local id = workspace:GetAttribute("ZZ_Emote")
	local panel = player.PlayerGui:FindFirstChild("AlphabetFallDance")
	if panel and panel:FindFirstChild("Emotes") then
		panel.Emotes.Visible = true
	end
	local controllers = player.PlayerScripts:FindFirstChild("Controllers", true)
	local ok = pcall(function()
		require(controllers.EmoteController).play(id)
	end)
	task.wait(1.2)
	local tracks = {}
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, t in humanoid:FindFirstChildOfClass("Animator"):GetPlayingAnimationTracks() do
			table.insert(
				tracks,
				string.format(
					"%s(%s len=%.1f)",
					t.Name,
					t.Animation and t.Animation.AnimationId:match("%d+") or "?",
					t.Length
				)
			)
		end
	end
	report:FireServer(
		`EMOTE {id} called={ok} rig={humanoid and humanoid.RigType.Name} tracks: `
			.. table.concat(tracks, ", ")
	)
end)

-- Сценарий просит салют (Controllers/FireworksController): кадр ставит ZZ_Shot следом.
workspace:GetAttributeChangedSignal("ZZ_Fireworks"):Connect(function()
	task.delay(0.3, function()
		local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
		require(client.Controllers.FireworksController).show()
		report:FireServer("fireworks shown")
	end)
end)
-- Итог испытания глазами клиента: пройден ли уровень (тогда будет салют).
task.spawn(function()
	local net = ReplicatedStorage:WaitForChild("Net", 30)
	local ending = net and net:WaitForChild("ChallengeEnd", 30)
	if ending then
		ending.OnClientEvent:Connect(function(result)
			report:FireServer(
				`challenge end: stars {result.stars} levelCleared {tostring(result.levelCleared)} reason {tostring(
					result.reason
				)}`
			)
		end)
	end
end)

-- Раз в секунду: что под ногами у персонажа на клиенте.
local lastLine = ""
while true do
	task.wait(1)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -60, 0), params)
		local venues = workspace:FindFirstChild("Venues")
		local line = string.format(
			"root %.0f,%.0f,%.0f anchored=%s state=%s below=%s venues=%s",
			root.Position.X,
			root.Position.Y,
			root.Position.Z,
			tostring(root.Anchored),
			(function()
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				return if humanoid
					then humanoid:GetState().Name .. (if humanoid.Sit then "+sit" else "")
					else "?"
			end)(),
			hit and (hit.Instance:GetFullName() .. " @" .. string.format("%.1f", hit.Distance)) or "nothing",
			venues and tostring(#venues:GetDescendants()) or "none"
		)
		if line ~= lastLine then
			report:FireServer(line)
			lastLine = line
		end
		-- Сценарий просит следить за клиентскими моделями (белки, змеи): где они сейчас.
		local track = workspace:GetAttribute("ZZ_Track")
		if track then
			for _, model in workspace:GetDescendants() do
				if model:IsA("Model") and model.Name == track then
					local pivot = model:GetPivot().Position
					local body = model:FindFirstChild("Body")
					local at = if body then body.Position else pivot
					report:FireServer(string.format("TRACK %s %.1f,%.1f,%.1f", track, at.X, at.Y, at.Z))
				end
			end
		end
	end
end
