--!nonstrict
--[[
	Клиентская часть «Пузырей». Правила — Challenges/Bubbles на сервере.

	Пузыри — анкерные прозрачные шары, без физики (docs/07-TECH-ARCH.md § 8):
	каждый кадр ставятся на своё место по времени. Колонка и фаза приходят
	с сервера, высота считается по кругу — доплыв доверху, пузырь снова внизу,
	так что упустить нужный нельзя.

	Лопнул верный — пузырь вспыхивает и исчезает. Не тот — становится рыбкой
	и уплывает в сторону: «мимо», а не наказание (docs/03-CHALLENGES.md § 5).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local AudioController = require(script.Parent.AudioController)
local Glyph = require(script.Parent.Parent.UI.Glyph)
local HUD = require(script.Parent.Parent.UI.HUD)

local BubblesController = {}

local FOLDER_NAME = "AlphabetFall_Bubbles"
local BUBBLE_SIZE = 3.8
local COLUMN_STEP = 4.6
local DISTANCE = 16 -- насколько впереди ребёнка всплывают пузыри

local player = Players.LocalPlayer

local spec: any = nil
local folder: Folder? = nil
local origin = CFrame.new()
local startedAt = 0
local blockedUntil = 0
local bubbles: { [number]: BasePart } = {}
local heartbeat: RBXScriptConnection? = nil

local function resolveOrigin(): CFrame
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		-- Только направление взгляда, без наклона: иначе столб пузырей кренится вместе с камерой.
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		end
		local base = root.Position + flat.Unit * DISTANCE - Vector3.new(0, 3, 0)
		return CFrame.lookAt(base, base + flat.Unit)
	end
	return CFrame.new(0, 2, 0)
end

local function positionOf(item: any, elapsed: number): CFrame
	local params = spec.params
	local cycle = params.height / params.riseSpeed
	local height = ((elapsed / cycle + item.phase) % 1) * params.height
	local x = (item.column - (params.columns + 1) / 2) * COLUMN_STEP
	-- Лёгкое покачивание: пузыри живые, но не прыгают — ловить их не надо.
	x += math.sin(elapsed * 1.3 + item.index) * 0.35
	return origin * CFrame.new(x, height, 0)
end

local function makeBubble(item: any): BasePart
	local letter = Letters.expect(item.letterId)

	local part = Instance.new("Part")
	part.Name = `Bubble_{item.index}`
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * BUBBLE_SIZE
	part.Color = letter.color:Lerp(Color3.new(1, 1, 1), 0.35)
	part.Material = Enum.Material.Glass
	part.Transparency = 0.35
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CastShadow = false
	part.Parent = folder

	Glyph.attach(part, letter.glyph, 0.8)

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 200
	click.Parent = part
	click.MouseClick:Connect(function()
		if not spec or os.clock() < blockedUntil then
			return
		end
		RemoteDefs.event("ChallengeAction"):FireServer({ itemIndex = item.index })
	end)

	return part
end

local function step()
	if not spec then
		return
	end
	local elapsed = os.clock() - startedAt
	local blocked = os.clock() < blockedUntil
	for index, part in bubbles do
		local item = spec.params.items[index]
		part.CFrame = positionOf(item, elapsed)
		-- Пауза после промаха видна глазами: пузыри притушены и не лопаются.
		part.Transparency = if blocked then 0.7 else 0.35
		Glyph.setTransparency(part, if blocked then 0.6 else 0)
	end
end

local function pop(part: BasePart)
	local tween = TweenService:Create(
		part,
		TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = part.Size * 1.6, Transparency = 1 }
	)
	tween.Completed:Connect(function()
		part:Destroy()
	end)
	Glyph.setTransparency(part, 1)
	tween:Play()
end

-- Не тот пузырь: он становится рыбкой и уплывает в сторону.
local function swimAway(part: BasePart)
	part.Color = Color3.fromRGB(255, 170, 80)
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0
	local billboard = part:FindFirstChild("GlyphBillboard")
	local label = billboard and billboard:FindFirstChild("Glyph")
	if label and label:IsA("TextLabel") then
		label.Text = "🐟"
	end
	Glyph.setTransparency(part, 0)
	local away = part.CFrame * CFrame.new(if math.random() < 0.5 then -24 else 24, 2, 0)
	local tween = TweenService:Create(
		part,
		TweenInfo.new(1.6, Enum.EasingStyle.Sine),
		{ CFrame = away, Transparency = 1 }
	)
	tween.Completed:Connect(function()
		part:Destroy()
	end)
	tween:Play()
end

function BubblesController.start(newSpec: any)
	BubblesController.stop()
	spec = newSpec
	startedAt = os.clock()
	blockedUntil = 0
	origin = resolveOrigin()

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = workspace
	folder = container

	for _, item in spec.params.items do
		bubbles[item.index] = makeBubble(item)
	end
	step()
	heartbeat = RunService.Heartbeat:Connect(step)

	HUD.showTarget(spec.params.targetGlyph, 0, spec.targetCount)
	task.delay(0.6, function()
		if spec == newSpec then
			AudioController.speak(spec.params.targetVO)
		end
	end)
end

function BubblesController.feedback(fb: any)
	if not spec then
		return
	end
	local part = bubbles[fb.itemIndex]
	if part then
		bubbles[fb.itemIndex] = nil
		if fb.correct then
			pop(part)
		else
			swimAway(part)
		end
	end

	HUD.showTarget(spec.params.targetGlyph, fb.caught, fb.targetCount)

	if not fb.correct then
		blockedUntil = os.clock() + (fb.cooldown or 0)
		-- «Это буква Ш. А нам нужна Щ» — ошибка становится подсказкой.
		local tapped = fb.tappedLetterId and Letters.get(fb.tappedLetterId)
		if tapped then
			task.delay(0.4, function()
				AudioController.speak(tapped.vo.name)
				task.wait(0.8)
				if spec then
					AudioController.speak(spec.params.targetVO)
				end
			end)
		end
	end
end

function BubblesController.stop()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	bubbles = {}
	spec = nil
	blockedUntil = 0
end

return BubblesController
