--!nonstrict
--[[
	Картинки (Config/Playground.PICTURES, мольберт и круги строит PlaygroundService).

	На мольберте картинка — арбуз, банан, волк, — под ней слово без первой буквы:
	«_РБУЗ». Перед мольбертом три круга с буквами. Встал на круг с той буквой,
	с которой начинается слово, — круг вспыхивает зелёным, голос называет букву
	и хвалит, через секунду новая картинка. Чужая буква краснеет и булькает,
	голос говорит «Это другая буква». Три верных — задание дня (ParkReport).

	Всё на клиенте: у каждого ребёнка своя загадка, сеть не тратится.
	Картинки — из справочника букв (Letters.picture, Letters.example): там,
	где слово начинается с самой буквы. Й (чай), Ъ, Ы и Ь в загадки не идут.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Playground = require(Shared.Config.Playground)
local AudioRegistry = require(Shared.Config.AudioRegistry)

local AudioController = require(script.Parent.AudioController)
local ParkReport = require(script.Parent.ParkReport)
local HUD = require(script.Parent.Parent.UI.HUD)

local PictureController = {}

local player = Players.LocalPlayer

local NEAR = 45 -- ближе этого к мольберту загадка оживает
local PAD_COLOR = Color3.fromRGB(255, 255, 255)
local RIGHT_COLOR = Color3.fromRGB(120, 225, 120)
local WRONG_COLOR = Color3.fromRGB(240, 110, 110)
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

type Pad = { part: BasePart, slot: number, label: TextLabel?, letterId: string? }

local board: BasePart? = nil
local picture: TextLabel? = nil
local word: TextLabel? = nil
local pads: { [number]: Pad } = {}
local pool: { string } = {}
local target: string? = nil
local hits = 0
local standing: number? = nil -- на каком круге стоит ребёнок: решаем один раз за шаг
local busy = false -- после ответа, пока меняется картинка

-- Буква годится в загадку, если слово-пример начинается с неё самой.
local function guessable(letterId: string): boolean
	local letter = Letters.expect(letterId)
	return letter.picture ~= nil
		and letter.example ~= nil
		and utf8.char(utf8.codepoint(letter.example, 1)) == letter.glyph
end

-- Загадки — из выученных букв и первых двух ступеней, как у рыбалки и тира.
function PictureController.update(snapshot: any)
	local list: { string } = {}
	local function add(id: string)
		if guessable(id) and not table.find(list, id) then
			table.insert(list, id)
		end
	end
	for _, stage in { 1, 2 } do
		for _, id in Letters.byStage(stage) do
			add(id)
		end
	end
	if typeof(snapshot) == "table" and typeof(snapshot.mastery) == "table" then
		for _, id in Letters.ordered() do
			if (tonumber(snapshot.mastery[id]) or 0) >= 1 then
				add(id)
			end
		end
	end
	pool = list
end

local function playKey(key: string, at: Vector3, volume: number)
	local id = AudioRegistry.ids[key]
	if not id or id == "" then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Parent = workspace.Terrain
	holder.WorldPosition = at
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMaxDistance = 80
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 4)
end

local function confetti(at: Vector3)
	local holder = Instance.new("Attachment")
	holder.Parent = workspace.Terrain
	holder.WorldPosition = at
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLES
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 230, 110), Color3.fromRGB(120, 225, 120))
	emitter.Size = NumberSequence.new(0.6, 0.1)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.LightEmission = 0.6
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(24)
	Debris:AddItem(holder, 2)
end

-- Буква лежит на круге: прозрачная пластина над ним, надпись читается от площади.
local function padLabel(pad: Pad): TextLabel?
	if pad.label and pad.label.Parent then
		return pad.label
	end
	local b = board
	if not b then
		return nil
	end
	local plate = Instance.new("Part")
	plate.Name = "PadGlyph"
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.Transparency = 1
	local side = Playground.PICTURES.padRadius * 1.5
	plate.Size = Vector3.new(side, 0.05, side)
	-- Все буквы смотрят одинаково — к мольберту, как стоит ребёнок, а не на его середину.
	local at = pad.part.Position + Vector3.new(0, 0.22, 0)
	local facing = -b.CFrame.LookVector * Vector3.new(1, 0, 1)
	plate.CFrame = CFrame.lookAt(at, at + facing)
	plate.Parent = pad.part
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100 / side -- TextScaled не рисует выше 100 пикселей
	gui.LightInfluence = 0
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.Rotation = 90 -- верх надписи на верхней грани смотрит вбок
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextStrokeColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	pad.label = label
	return label
end

local function boardLabels()
	local b = board
	if not b or (picture and picture.Parent) then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Picture"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = b
	local image = Instance.new("TextLabel")
	image.Size = UDim2.fromScale(1, 0.75)
	image.BackgroundTransparency = 1
	image.TextScaled = true
	image.Parent = gui
	picture = image
	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.fromScale(1, 0.22)
	caption.Position = UDim2.fromScale(0, 0.76)
	caption.BackgroundTransparency = 1
	caption.TextScaled = true
	caption.Font = Enum.Font.FredokaOne
	caption.TextColor3 = Color3.fromRGB(90, 70, 60)
	caption.Parent = gui
	word = caption
end

local function shuffled(list: { string }): { string }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function newRiddle()
	if #pool < Playground.PICTURES.pads then
		return
	end
	boardLabels()
	local previous = target
	local choices = {}
	for _, id in pool do
		if id ~= previous then
			table.insert(choices, id)
		end
	end
	target = choices[math.random(1, #choices)]
	local letter = Letters.expect(target :: string)
	if picture then
		picture.Text = letter.picture
	end
	if word then
		-- Слово без первой буквы: «_РБУЗ». Взрослому подсказка, ребёнку — картинка.
		word.Text = "_" .. string.sub(letter.example, utf8.offset(letter.example, 2) :: number)
	end
	-- Три разные буквы на кругах, среди них нужная — на случайном месте.
	local others = {}
	for _, id in shuffled(pool) do
		if id ~= target and #others < Playground.PICTURES.pads - 1 then
			table.insert(others, id)
		end
	end
	table.insert(others, math.random(1, #others + 1), target)
	for slot, pad in pads do
		pad.letterId = others[slot]
		local label = padLabel(pad)
		if label and pad.letterId then
			local shown = Letters.expect(pad.letterId)
			label.Text = shown.glyph
			label.TextColor3 = shown.color
		end
		pad.part.Color = PAD_COLOR
	end
end

local function flash(pad: Pad, color: Color3)
	pad.part.Color = color
	pad.part.Material = Enum.Material.Neon
	task.delay(0.8, function()
		pad.part.Color = PAD_COLOR
		pad.part.Material = Enum.Material.SmoothPlastic
	end)
end

local function answer(pad: Pad)
	if busy or not target or not pad.letterId then
		return
	end
	if pad.letterId == target then
		busy = true
		hits += 1
		flash(pad, RIGHT_COLOR)
		confetti(pad.part.Position + Vector3.new(0, 1, 0))
		playKey("sfx_crystal", pad.part.Position, 0.7)
		local letter = Letters.expect(target :: string)
		AudioController.speakPhrase({ letter.vo.name, string.format("praise_%02d", math.random(1, 8)) })
		if hits == Playground.PICTURES.goal then
			ParkReport.done("pictures")
			task.delay(1, HUD.toast, "🖼 Три картинки! Ты знаешь буквы!", 4)
		end
		task.delay(Playground.PICTURES.next, function()
			busy = false
			newRiddle()
		end)
	else
		flash(pad, WRONG_COLOR)
		playKey("sfx_run_bloop", pad.part.Position, 0.8)
		AudioController.speak("retry_03") -- «Это другая буква.»
	end
end

local function step()
	local b = board
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not b or not root then
		return
	end
	local near = (root.Position - b.Position).Magnitude < NEAR
	if near and not target and not busy then
		newRiddle()
	end
	if not near then
		standing = nil
		return
	end
	local on: number? = nil
	for slot, pad in pads do
		local offset = root.Position - pad.part.Position
		if
			Vector2.new(offset.X, offset.Z).Magnitude < Playground.PICTURES.padRadius
			and offset.Y > 0
			and offset.Y < 5
		then
			on = slot
		end
	end
	-- Решаем один раз, когда ребёнок наступил: стоять на круге и ждать можно.
	if on ~= standing then
		standing = on
		if on and pads[on] then
			answer(pads[on])
		end
	end
end

-- Для стенда проверки: где круги, что загадано, сколько угадано.
function PictureController.debug()
	local list = {}
	for slot, pad in pads do
		list[slot] = { letterId = pad.letterId, position = pad.part.Position }
	end
	return { target = target, hits = hits, pads = list, board = if board then board.Position else nil }
end

function PictureController.init()
	local function watchTag(tag: string, set: (BasePart) -> ())
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
			if instance:IsA("BasePart") then
				set(instance)
			end
		end)
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("BasePart") then
				set(instance)
			end
		end
	end
	watchTag("AF_PictureBoard", function(part)
		board = part
		picture = nil
		word = nil
		target = nil
	end)
	watchTag("AF_PicturePad", function(part)
		local slot = part:GetAttribute("Slot")
		if typeof(slot) == "number" then
			pads[slot] = { part = part, slot = slot }
			target = nil -- круг приехал заново (стриминг): загадку раздадим ещё раз
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return PictureController
