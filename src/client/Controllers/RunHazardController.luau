--!nonstrict
--[[
	Движение аттракционов забега и их касания (World/RunAttractions на сервере).

	Сервер ставит детали на место и вешает теги: RunMover — «двигай меня»,
	RunHurt — «сбиваю». Здесь каждое движение считается от серверных часов
	(workspace:GetServerTimeNow), поэтому вертушка у всех в одной фазе, а у
	ребёнка на экране крутится плавно — без рывков сетевой репликации.

	Касание проверяется тут же, по той картинке, которую ребёнок видит: сбил
	молот — значит, сбил. Сервер только возвращает к флажку и больше ничего
	не делает, так что подделывать касание незачем.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefs = require(Shared.Net.RemoteDefs)
local Attractions = require(Shared.Config.Attractions)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local RunSounds = require(Shared.Config.RunSounds)

local AudioController = require(script.Parent.AudioController)

local RunHazardController = {}

local MOVER_TAG = "RunMover"
local HURT_TAG = "RunHurt"
local BOUNCE_TAG = "RunBounce"
local WIND_TAG = "RunWind"

-- Насколько персонаж «шире» точки корня: полстуда вбок, ноги на три студа вниз.
local SIDE_MARGIN = 1
local FEET = 3.3
local HEAD = 2.5
local NEAR = 60 -- дальше этого движущиеся детали не двигаем и не проверяем
local HIT_COOLDOWN = 1.6
local SINK_EASE = 0.25 -- за сколько секунд кочка уходит в лаву и поднимается

local player = Players.LocalPlayer
local movers: { [BasePart]: boolean } = {}
local hurting: { [BasePart]: boolean } = {}
local lastHit = 0
local originalColor: { [BasePart]: Color3 } = {}
local lastCarry: { [BasePart]: { position: Vector3, time: number } } = {}
local bouncers: { [BasePart]: boolean } = {}
local lastBounce = 0

--[[
	Печеньки крошатся у каждого ребёнка свои: состояние живёт здесь, а не
	на сервере. Дети печеньки (кромка, крошка) падают вместе с ней.
]]
type Crumb = {
	state: "whole" | "crack" | "fall" | "gone",
	since: number,
	color: Color3,
	children: { [BasePart]: CFrame },
}
local crumbs: { [BasePart]: Crumb } = {}
local stomped: { [BasePart]: boolean } = {}

-- Участки тучек-ветродуев (тег RunWind) и какие из них сейчас дуют: для звука «фу-у-у».
local winds: { [BasePart]: boolean } = {}
local gusting: { [BasePart]: boolean } = {}

--[[
	Звуки аттракционов (Config/RunSounds). Звучат в мире, у детали, и только
	рядом с ребёнком. Метка цикла (cueMark) — номер полувзмаха или круга:
	сменилась — значит, молот прошёл низ, доска развернулась, валун покатился.
]]
local soundRandom = Random.new()
local lastRoot: Vector3? = nil
local cueMark: { [BasePart]: number } = {}

local function newSound(event: RunSounds.Event, parent: Instance): Sound?
	local id = AudioRegistry.ids[event.key]
	if not id or id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = event.volume
	if event.speed then
		sound.PlaybackSpeed = soundRandom:NextNumber(event.speed[1], event.speed[2])
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = RunSounds.HEAR
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = parent
	return sound
end

local function sound(kind: string, at: Vector3)
	local event = RunSounds.EVENTS[kind]
	if not event or (lastRoot and (lastRoot - at).Magnitude > RunSounds.HEAR) then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Name = "RunSound"
	holder.Parent = workspace.Terrain
	holder.Position = at
	local played = newSound(event, holder)
	if played then
		played:Play()
	end
	Debris:AddItem(holder, event.seconds)
end

-- Постоянный звук детали (лава булькает): играет сам, пока деталь есть.
local function loopOn(part: BasePart)
	local event = RunSounds.LOOPS[part:GetAttribute("Loop")]
	local looped = event and newSound(event, part)
	if looped then
		looped.Looped = true
		looped:Play()
	end
end

local function positionFor(part: BasePart, now: number): CFrame?
	local kind = part:GetAttribute("Mover")
	local base = part:GetAttribute("Base")
	if typeof(base) ~= "CFrame" then
		return nil
	end
	local period = part:GetAttribute("Period") or 1
	local phase = part:GetAttribute("Phase") or 0
	local offset = part:GetAttribute("Offset")
	if typeof(offset) ~= "CFrame" then
		offset = CFrame.identity
	end

	if kind == "spin" then
		local angle = 2 * math.pi * ((now + phase) / period)
		return base * CFrame.Angles(0, angle, 0) * offset
	elseif kind == "swing" then
		local amplitude = part:GetAttribute("Amplitude") or 0.5
		local angle = amplitude * math.sin(2 * math.pi * (now + phase) / period)
		return base * CFrame.Angles(0, 0, angle) * offset
	elseif kind == "roll" then
		local s = (now + phase) % period
		local travel = part:GetAttribute("Travel") or 0
		if s >= travel then
			part.Transparency = 1
			return base * CFrame.new(0, -200, 0)
		end
		part.Transparency = 0
		local speed = part:GetAttribute("Speed") or 10
		local radius = part:GetAttribute("Radius") or 5
		local distance = s * speed
		-- Последние полсекунды валун уходит в землю: он не исчезает, а проваливается.
		local sink = math.max(0, s - (travel - 0.5)) / 0.5 * radius * 2
		return base * CFrame.new(0, -sink, distance) * CFrame.Angles(distance / radius, 0, 0)
	elseif kind == "slide" then
		-- Облачко катается поперёк трассы: влево-вправо от середины.
		local travel = part:GetAttribute("Travel") or 0
		local x = travel * math.sin(2 * math.pi * (now + phase) / period)
		return base * CFrame.new(x, 0, 0) * offset
	elseif kind == "lift" then
		-- Подъёмник на шариках: вверх-вниз от середины своего хода.
		local travel = part:GetAttribute("Travel") or 0
		local y = travel * math.sin(2 * math.pi * (now + phase) / period)
		return base * CFrame.new(0, y, 0) * offset
	elseif kind == "scroll" then
		-- Полоска ленты транспортёра: едет вдоль оси и с конца возвращается к началу.
		local travel = part:GetAttribute("Travel") or 1
		local speed = part:GetAttribute("Speed") or 0
		local axis = part:GetAttribute("Axis")
		if typeof(axis) ~= "Vector3" then
			axis = Vector3.xAxis
		end
		local s = (now * speed + phase) % travel - travel / 2
		return base * CFrame.new(axis * s) * offset
	elseif kind == "pendulum" then
		-- Качели: верёвки ходят маятником вдоль бега, доска на их конце стоит ровно.
		local amplitude = part:GetAttribute("Amplitude") or 0.4
		local angle = amplitude * math.sin(2 * math.pi * (now + phase) / period)
		local swung = base * CFrame.Angles(angle, 0, 0)
		local hang = part:GetAttribute("Hang")
		if hang then
			return CFrame.new((swung * CFrame.new(0, -hang, 0)).Position) * base.Rotation * offset
		end
		return swung * offset
	elseif kind == "stomp" then
		-- Кубик-топотун: наверху, дрожь перед топотом, топот, медленный подъём.
		local down = part:GetAttribute("Down") or 1
		local lift = part:GetAttribute("Lift") or 10
		local s = now + phase
		local drop = Attractions.stomperDrop(s, period, down)
		local warning = Attractions.stomperWarning(s, period, down)
		if not originalColor[part] then
			originalColor[part] = part.Color
		end
		local warnColor = part:GetAttribute("WarnColor")
		part.Color = if warning and typeof(warnColor) == "Color3" then warnColor else originalColor[part]
		local shadowName = part:GetAttribute("Shadow")
		local shadow = shadowName and part.Parent and part.Parent:FindFirstChild(shadowName)
		if shadow and shadow:IsA("BasePart") then
			shadow.Transparency = if warning or drop > 0 then 0.3 else 0.72
		end
		-- Топнул: сообщаем один раз за цикл, в миг удара.
		local landed = drop >= 1
		if landed and not stomped[part] then
			sound("stomp", base.Position)
		end
		stomped[part] = landed
		local shake = if warning
			then CFrame.new(math.sin(now * 60) * 0.25, 0, math.cos(now * 47) * 0.25)
			else CFrame.identity
		return base * CFrame.new(0, lift * (1 - drop), 0) * shake
	elseif kind == "sink" then
		local s = (now + phase) % period
		local solid = part:GetAttribute("Solid") or period
		local warn = part:GetAttribute("Warn") or 0.8
		local depth = part:GetAttribute("Depth") or 4
		local warnColor = part:GetAttribute("WarnColor")
		if not originalColor[part] then
			originalColor[part] = part.Color
		end
		local down
		if s < solid then
			down = if s < SINK_EASE then 1 - s / SINK_EASE else 0
			local warning = s >= solid - warn
			part.Color = if warning and typeof(warnColor) == "Color3" then warnColor else originalColor[part]
		else
			down = math.min(1, (s - solid) / SINK_EASE)
			part.Color = originalColor[part]
		end
		return base * CFrame.new(0, -depth * down, 0)
	end
	return nil
end

-- Задела ли деталь персонажа: корень в пространстве детали с запасом на тело.
local function touches(part: BasePart, root: Vector3): boolean
	if part.Transparency >= 1 then
		return false
	end
	local size = part.Size
	if part.Shape == Enum.PartType.Ball then
		return (part.Position - root).Magnitude < size.X / 2 + SIDE_MARGIN + 0.3
	end
	local p = part.CFrame:PointToObjectSpace(root)
	local half = size / 2
	-- Цилиндр лежит осью по X: поперёк оси он круглый, считаем его коробкой — запас и так есть.
	return math.abs(p.X) < half.X + SIDE_MARGIN
		and math.abs(p.Z) < half.Z + SIDE_MARGIN
		and p.Y < half.Y + FEET
		and p.Y > -half.Y - HEAD
end

-- Стоит ли ребёнок на круглой детали, лежащей плашмя (цилиндр осью X вверх).
local function standsOn(part: BasePart, root: Vector3, radius: number): boolean
	local top = part.Position.Y + part.Size.X / 2
	local above = root.Y - top
	local flat = (root - part.Position) * Vector3.new(1, 0, 1)
	return flat.Magnitude < radius + 0.4 and above > 0 and above < FEET + 0.9
end

local function crumbOf(part: BasePart, base: CFrame): Crumb
	local crumb = crumbs[part]
	if crumb then
		return crumb
	end
	local children = {}
	for _, child in part:GetChildren() do
		if child:IsA("BasePart") then
			children[child] = base:ToObjectSpace(child.CFrame)
		end
	end
	crumb = { state = "whole", since = 0, color = part.Color, children = children }
	crumbs[part] = crumb
	return crumb
end

local function placeCrumb(part: BasePart, crumb: Crumb, cframe: CFrame, fade: number)
	part.CFrame = cframe
	part.Transparency = fade
	for child, offset in crumb.children do
		child.CFrame = cframe * offset
		child.Transparency = fade
	end
end

--[[
	Печенька: встал — трещит и темнеет, через Hold секунд падает вниз и тает,
	через Back вырастает на месте. Пока падает и её нет — сквозь неё
	проваливаешься: CanCollide меняет клиент, и физика персонажа у него же.
]]
local function crumble(part: BasePart, now: number, root: Vector3?)
	local base = part:GetAttribute("Base")
	if typeof(base) ~= "CFrame" then
		return
	end
	local crumb = crumbOf(part, base)
	local hold = part:GetAttribute("Hold") or 1
	local fall = part:GetAttribute("Fall") or 0.45
	local back = part:GetAttribute("Back") or 2.5
	local elapsed = now - crumb.since
	if crumb.state == "whole" then
		-- Цилиндр лежит на боку: радиус печеньки — половина Size.Y.
		if root and standsOn(part, root, part.Size.Y / 2) then
			crumb.state = "crack"
			crumb.since = now
			-- Чужая буквенная кочка не трещит, а булькает: «не сюда», а не «беги».
			sound(if part:GetAttribute("Sink") then "stone_sink" else "crack", part.Position)
		end
	elseif crumb.state == "crack" then
		local share = math.clamp(elapsed / hold, 0, 1)
		part.Color = crumb.color:Lerp(Color3.fromRGB(120, 80, 50), share)
		local shake = CFrame.new(0, math.sin(now * 70) * 0.08 * share, math.cos(now * 55) * 0.12 * share)
		placeCrumb(part, crumb, base * shake, 0)
		if elapsed >= hold then
			crumb.state = "fall"
			crumb.since = now
			part.CanCollide = false
			if not part:GetAttribute("Sink") then
				sound("crumble", part.Position)
			end
		end
	elseif crumb.state == "fall" then
		local share = math.clamp(elapsed / fall, 0, 1)
		placeCrumb(part, crumb, base - Vector3.new(0, 7 * share * share, 0), share)
		if elapsed >= fall then
			crumb.state = "gone"
			crumb.since = now
		end
	elseif crumb.state == "gone" and elapsed >= back then
		crumb.state = "whole"
		crumb.since = now
		part.Color = crumb.color
		part.CanCollide = true
		placeCrumb(part, crumb, base, 0)
	end
end

--[[
	Верная буквенная кочка: встал — вспыхивает, звенит и называет свою букву.
	Не чаще раза в пару секунд на кочку: стоящий на ней не слышит букву пулемётом.
]]
local stoneSaid: { [BasePart]: number } = {}

local originalMaterial: { [BasePart]: Enum.Material } = {}

-- true — ребёнок только что встал на кочку (или доску моста), а не стоит на ней давно.
local function letterstone(part: BasePart, now: number, root: Vector3?): boolean
	if not root or not standsOn(part, root, part.Size.Y / 2) then
		return false
	end
	if (stoneSaid[part] or -math.huge) + 2.5 > now then
		return false
	end
	stoneSaid[part] = now
	sound("stone_right", part.Position)
	local vo = part:GetAttribute("Vo")
	if typeof(vo) == "string" then
		AudioController.speak(vo)
	end
	local color = originalColor[part] or part.Color
	originalColor[part] = color
	local material = originalMaterial[part] or part.Material
	originalMaterial[part] = material
	part.Color = Color3.fromRGB(150, 235, 150)
	part.Material = Enum.Material.Neon
	task.delay(0.6, function()
		if part.Parent then
			part.Color = color
			part.Material = material
		end
	end)
	return true
end

--[[
	Доска моста из букв (RunAttractions.letterbridge): верная звенит и называет
	букву, как кочка, а ещё от прошлой верной доски (или от плиты-начала)
	к ней ложится настил. Дошёл до конца — за спиной целый мост по алфавиту.
	Настил — только у этого ребёнка: забег свой у каждого.
]]
local bridged: { [BasePart]: boolean } = {}

local function bridgestep(part: BasePart, now: number, root: Vector3?)
	if not letterstone(part, now, root) or bridged[part] then
		return
	end
	bridged[part] = true
	local row = part:GetAttribute("Row")
	local ride = part:GetAttribute("Ride")
	local parent = part.Parent
	if typeof(row) ~= "number" or not parent then
		return
	end
	local previous: BasePart? = nil
	for _, sibling in parent:GetChildren() do
		if not sibling:IsA("BasePart") or sibling:GetAttribute("Ride") ~= ride then
			continue
		end
		local isStart = row == 1 and string.sub(sibling.Name, 1, 12) == "BridgeStart_"
		local isPrevious = sibling:GetAttribute("Mover") == "bridgestep"
			and sibling:GetAttribute("Row") == row - 1
		if isStart or isPrevious then
			previous = sibling
			break
		end
	end
	if not previous then
		return
	end
	-- С плиты-начала настил идёт от её точки напротив доски, а не от середины.
	local from = previous.Position
	if row == 1 then
		from = (previous.CFrame * CFrame.new(previous.CFrame:PointToObjectSpace(part.Position).X, 0, 0)).Position
	end
	local to = part.Position
	local plank = Instance.new("Part")
	plank.Name = "BridgePlank"
	plank.Anchored = true
	plank.Material = Enum.Material.WoodPlanks
	plank.Color = Color3.fromRGB(250, 205, 120)
	plank.Size = Vector3.new(2.6, 0.6, (to - from).Magnitude)
	plank.CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.new(0, 0.2, 0)
	plank.Transparency = 1
	plank.Parent = parent
	TweenService:Create(plank, TweenInfo.new(0.4), { Transparency = 0 }):Play()
end

--[[
	Батут: приземлился на сетку — толчок вверх. Сила (Bounce) посчитана
	на сервере так, чтобы ноги поднялись выше островка.
]]
local function bounceCheck(root: BasePart)
	local now = os.clock()
	if now - lastBounce < 0.35 then
		return
	end
	local position = root.Position
	for pad in bouncers do
		if not pad.Parent then
			bouncers[pad] = nil
			continue
		end
		local radius = pad:GetAttribute("BounceRadius") or pad.Size.Y / 2
		if (pad.Position - position).Magnitude > radius + 8 then
			continue
		end
		if root.AssemblyLinearVelocity.Y <= 2 and standsOn(pad, position, radius) then
			lastBounce = now
			--[[
				Простой толчок персонаж гасит за кадр: стоя на земле, он держит
				себя на высоте ног. Поэтому — свободный полёт и десятую долю
				секунды LinearVelocity, только по вертикали: рулить в воздухе
				вбок ребёнок может, как в обычном прыжке.
			]]
			local power = pad:GetAttribute("Bounce") or 70
			local humanoid = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end
			local velocity = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, power, velocity.Z)
			local attachment = Instance.new("Attachment")
			attachment.Parent = root
			local push = Instance.new("LinearVelocity")
			push.Attachment0 = attachment
			push.RelativeTo = Enum.ActuatorRelativeTo.World
			push.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
			push.LineDirection = Vector3.yAxis
			push.LineVelocity = power
			push.MaxForce = 1e6
			push.Parent = root
			task.delay(0.1, function()
				push:Destroy()
				attachment:Destroy()
			end)
			sound("bounce", pad.Position)
			return
		end
	end
end

local function meshScale(model: Instance, name: string, scale: Vector3)
	local p = model:FindFirstChild(name)
	local mesh = p and p:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.Scale = scale
	end
end

--[[
	Ветродуй: тучка по циклу надувает щёки, отклоняется назад — и дует,
	зажмурившись. Кто на её участке и не за щитом, того сносит: корень
	сдвигается по ветру каждый кадр. Толчок скоростью персонаж погасил бы
	сам, а сдвиг — нет: против ветра остаётся только упираться.
]]
local function windStep(zone: BasePart, now: number, root: BasePart?, dt: number)
	local period = zone:GetAttribute("Period") or 5
	local gust = zone:GetAttribute("Gust") or 1.5
	local phase = zone:GetAttribute("Phase") or 0
	local s = now + phase
	local strength = Attractions.windGust(s, period, gust)
	local warning = Attractions.windWarning(s, period, gust)
	local cycle = s % period
	local startAt = period - gust
	-- Насколько надуты щёки: растут, пока тучка набирает воздух, и сдуваются за порыв.
	local puff = if warning
		then (cycle - (startAt - Attractions.WIND_WARN)) / Attractions.WIND_WARN
		elseif cycle >= startAt then 1 - (cycle - startAt) / gust
		else 0

	local model = zone.Parent
	local cloud = model and model:FindFirstChild(zone:GetAttribute("Cloud") or "")
	if cloud and cloud:IsA("Model") then
		local base = cloud:GetAttribute("Base")
		if typeof(base) == "CFrame" then
			-- Набирая воздух, тучка отклоняется назад; дуя — подаётся к мостику.
			local lean = if warning then 1.4 * puff else -1.2 * strength
			cloud:PivotTo(base * CFrame.new(0, math.sin(now * 1.6 + phase) * 0.35, lean))
		end
		local cheeks = Vector3.one * (1 + 0.8 * puff)
		meshScale(cloud, "CheekL", cheeks)
		meshScale(cloud, "CheekR", cheeks)
		local squint = strength > 0
		local eyes = if squint then Vector3.new(1.1, 0.22, 1) else Vector3.one
		meshScale(cloud, "EyeL", eyes)
		meshScale(cloud, "EyeR", eyes)
		for _, name in { "ShineL", "ShineR" } do
			local shine = cloud:FindFirstChild(name)
			if shine then
				shine.Transparency = if squint then 1 else 0
			end
		end
		meshScale(
			cloud,
			"Mouth",
			if squint
				then Vector3.new(1, 1.3, 1)
				elseif warning then Vector3.new(0.5, 0.35, 1)
				else Vector3.one * 0.8
		)
		local stream = cloud:FindFirstChild("Stream")
		local emitter = stream and stream:FindFirstChildOfClass("ParticleEmitter")
		if emitter then
			emitter.Enabled = strength > 0.3
		end
		-- Линии ветра: видны в порыв и извиваются, как ленточки.
		for line = 1, 3 do
			local beam = stream and stream:FindFirstChild(`Line{line}`)
			if beam and beam:IsA("Beam") then
				beam.Enabled = strength > 0.05
				if strength > 0.05 then
					local wave = now * 7 + line * 1.3
					beam.CurveSize0 = 2.5 * math.sin(wave)
					beam.CurveSize1 = -2.5 * math.sin(wave + 1.1)
					beam.Width0 = 0.9 * strength
				end
			end
		end
		local blowing = strength > 0
		if blowing and not gusting[zone] then
			sound("blow", cloud:GetPivot().Position)
		end
		gusting[zone] = blowing
	end

	-- Флажок на щите: висит, пока тихо, вытягивается по ветру и трепещет в порыв.
	local flag = model and model:FindFirstChild(zone:GetAttribute("Flag") or "")
	if flag and flag:IsA("BasePart") then
		local top = flag:GetAttribute("Base")
		if typeof(top) == "CFrame" then
			local droop = 1.35 * (1 - strength)
			local flutter = math.sin(now * 19 + phase) * 0.25 * strength
			flag.CFrame = top
				* CFrame.Angles(0, flutter, -droop)
				* CFrame.new(flag.Size.X / 2, -flag.Size.Y / 2, 0)
		end
	end

	if not root or strength <= 0 then
		return
	end
	local p = zone.CFrame:PointToObjectSpace(root.Position)
	local half = zone.Size / 2
	if math.abs(p.X) > half.X or math.abs(p.Y) > half.Y or math.abs(p.Z) > half.Z then
		return
	end
	-- Щит стоит посреди участка: в его длину по ходу ветра нет.
	if math.abs(p.Z) < (zone:GetAttribute("ShelterHalf") or 0) then
		return
	end
	local wind = zone:GetAttribute("Wind")
	if typeof(wind) == "Vector3" then
		root.CFrame += wind * strength * dt
	end
end

local function onHit()
	local now = os.clock()
	if now - lastHit < HIT_COOLDOWN then
		return
	end
	lastHit = now
	RemoteDefs.event("RunHazard"):FireServer()
end

local function step(frame: number)
	if next(movers) == nil and next(hurting) == nil and next(bouncers) == nil and next(winds) == nil then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootPosition = root and root.Position
	lastRoot = rootPosition
	local now = workspace:GetServerTimeNow()

	for part in movers do
		if not part.Parent then
			movers[part] = nil
			lastCarry[part] = nil
			continue
		end
		local base = part:GetAttribute("Base")
		if rootPosition and typeof(base) == "CFrame" and (base.Position - rootPosition).Magnitude > NEAR then
			lastCarry[part] = nil
			continue
		end
		-- Лента транспортёра стоит на месте, а везёт: скорость закреплённой детали.
		local beltVelocity = part:GetAttribute("Belt")
		if typeof(beltVelocity) == "Vector3" and typeof(base) == "CFrame" then
			part.AssemblyLinearVelocity = base:VectorToWorldSpace(beltVelocity)
			continue
		end
		if part:GetAttribute("Mover") == "crumble" then
			crumble(part, now, rootPosition)
			continue
		end
		if part:GetAttribute("Mover") == "letterstone" then
			letterstone(part, now, rootPosition)
			continue
		end
		if part:GetAttribute("Mover") == "bridgestep" then
			bridgestep(part, now, rootPosition)
			continue
		end
		local cframe = positionFor(part, now)
		if cframe then
			part.CFrame = cframe
			local cue = part:GetAttribute("Sound")
			if cue then
				local t = (now + (part:GetAttribute("Phase") or 0)) / (part:GetAttribute("Period") or 1)
				local mark = if cue == "roll"
					then math.floor(t)
					elseif cue == "creak" then math.floor(2 * t + 0.5)
					else math.floor(2 * t)
				if cueMark[part] and cueMark[part] ~= mark then
					sound(cue, cframe.Position)
				end
				cueMark[part] = mark
			end
			if part:GetAttribute("Carry") and part:GetAttribute("Mover") ~= "slide" then
				-- Доска качелей: скорость — сдвиг с прошлого кадра. После паузы — ноль, а не рывок.
				local last = lastCarry[part]
				local dt = if last then now - last.time else 0
				part.AssemblyLinearVelocity = if last
						and dt > 0
						and dt < 0.25
					then (cframe.Position - last.position) / dt
					else Vector3.zero
				lastCarry[part] = { position = cframe.Position, time = now }
				continue
			end
			--[[
				Везёт стоящего: у закреплённой детали скорость — это «лента
				транспортёра», и персонаж на облаке едет вместе с ним, а не
				соскальзывает. Скорость — производная того же движения.
			]]
			if part:GetAttribute("Carry") then
				local period = part:GetAttribute("Period") or 1
				local travel = part:GetAttribute("Travel") or 0
				local phase = part:GetAttribute("Phase") or 0
				local speed = travel * 2 * math.pi / period * math.cos(2 * math.pi * (now + phase) / period)
				part.AssemblyLinearVelocity = (base :: CFrame).RightVector * speed
			end
		end
	end

	for zone in winds do
		if not zone.Parent then
			winds[zone] = nil
			gusting[zone] = nil
			continue
		end
		if rootPosition and (zone.Position - rootPosition).Magnitude > NEAR + 20 then
			continue
		end
		windStep(zone, now, root, math.min(frame, 0.1))
	end

	if not rootPosition then
		return
	end
	bounceCheck(root)
	for part in hurting do
		if not part.Parent then
			hurting[part] = nil
			continue
		end
		if (part.Position - rootPosition).Magnitude < NEAR and touches(part, rootPosition) then
			onHit()
			return
		end
	end
end

local function watch(tag: string, set: { [BasePart]: boolean })
	local function add(instance: Instance)
		if instance:IsA("BasePart") then
			set[instance] = true
			if instance:GetAttribute("Loop") and not instance:FindFirstChildOfClass("Sound") then
				loopOn(instance)
			end
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		set[instance :: BasePart] = nil
		originalColor[instance :: BasePart] = nil
		lastCarry[instance :: BasePart] = nil
		crumbs[instance :: BasePart] = nil
		cueMark[instance :: BasePart] = nil
		stomped[instance :: BasePart] = nil
		gusting[instance :: BasePart] = nil
	end)
end

function RunHazardController.init()
	watch(MOVER_TAG, movers)
	watch(HURT_TAG, hurting)
	watch(BOUNCE_TAG, bouncers)
	watch(WIND_TAG, winds)
	RunService.RenderStepped:Connect(step)
end

-- Для тестов: где деталь стоит в момент now.
RunHazardController.positionFor = positionFor
RunHazardController.touches = touches

return RunHazardController
