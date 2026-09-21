--!strict
--[[
	Катания парка на клиенте (Config/Rides): паровозик по кругу на эстакаде
	и колесо обозрения. Сервер поставил детали и метки; здесь они едут
	по серверным часам — у всех детей поезд в одном месте, колесо в одной фазе.

	Прокатиться: встал на жёлтый посадочный круг — сел. Поезд берёт пассажиров,
	только стоя у платформы (круг тогда зелёный), и привозит обратно через круг.
	Колесо сажает в нижнюю кабинку сразу и возит один оборот. Прыжок — сойти
	где угодно: упасть с высоты в этой игре не страшно, дно — трава.

	Пассажир не приварен к вагону: персонаж ребёнка принадлежит его клиенту,
	и клиент каждый кадр ставит его на сиденье. Серверу это видно как обычное
	движение персонажа, другим детям — тоже.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rides = require(Shared.Config.Rides)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local AudioController = require(script.Parent.AudioController)

local RideController = {}

local ANIMATE_DISTANCE = 450 -- колесо дальше этого не крутим: его почти не видно
local PAD_RADIUS = 2.8
local PASSENGER_CAR = 2 -- первый вагончик за паровозом
local SEAT_HEIGHT = 1.8 -- корень персонажа над полом, когда он сидит

local PAD_READY = Color3.fromRGB(110, 230, 120)
local PAD_WAIT = Color3.fromRGB(250, 205, 70)

type Group = { parts: { BasePart }, offsets: { CFrame } }

local player = Players.LocalPlayer

-- Детали группы и их положения относительно опорной точки.
local function collect(root: Instance, home: CFrame): Group
	local group: Group = { parts = {}, offsets = {} }
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(group.parts, descendant)
			table.insert(group.offsets, home:ToObjectSpace(descendant.CFrame))
		end
	end
	return group
end

local frames: { CFrame } = {}
local function move(group: Group, at: CFrame)
	table.clear(frames)
	for index, offset in group.offsets do
		frames[index] = at * offset
	end
	workspace:BulkMoveTo(group.parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- ===== Поезд =====

type Train = { cars: { Group }, smoke: ParticleEmitter?, chimney: BasePart?, wasStanding: boolean? }
local train: Train? = nil

local attachTrain: (Instance) -> ()
function attachTrain(model: Instance)
	local cars: { Group } = {}
	local smoke: ParticleEmitter? = nil
	local chimney: BasePart? = nil
	for index = 1, Rides.TRAIN.cars do
		local car = model:FindFirstChild(`Car_{index}`)
		local home = car and car:GetAttribute("Home")
		if not car or typeof(home) ~= "CFrame" then
			-- Вагоны ещё не доехали по сети: попробуем чуть позже.
			if model.Parent then
				task.delay(2, attachTrain, model)
			end
			return
		end
		cars[index] = collect(car, home)
	end
	local emitter = model:FindFirstChild("Smoke", true)
	if emitter and emitter:IsA("ParticleEmitter") then
		smoke = emitter
		chimney = emitter.Parent :: BasePart
	end
	train = { cars = cars, smoke = smoke, chimney = chimney }
end

local function whistle(at: BasePart?)
	local id = AudioRegistry.ids.amb_train_whistle
	if not at or not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.8
	sound.RollOffMaxDistance = 220
	sound.RollOffMinDistance = 20
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = at
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function stepTrain(now: number)
	local current = train
	if not current then
		return
	end
	local head, standing = Rides.trainAt(now)
	for index, group in current.cars do
		move(group, Rides.trackFrame(Rides.carAngle(head, index)))
	end
	if current.smoke then
		current.smoke.Rate = if standing then 1.5 else 7
	end
	if current.wasStanding == true and not standing then
		whistle(current.chimney)
	end
	current.wasStanding = standing
end

-- ===== Колесо =====

type Wheel = { model: Instance, axle: CFrame, rotor: Group, cabins: { Group } }
local wheels: { [Instance]: Wheel } = {}

local attachWheel: (Instance) -> ()
function attachWheel(model: Instance)
	local axle = model:GetAttribute("Axle")
	local rotorModel = model:FindFirstChild("Rotor")
	if typeof(axle) ~= "CFrame" or not rotorModel then
		return
	end
	local cabins: { Group } = {}
	for index = 1, Rides.WHEEL.cabins do
		local cabin = model:FindFirstChild(`Cabin_{index}`)
		if not cabin then
			if model.Parent then
				task.delay(2, attachWheel, model)
			end
			return
		end
		cabins[index] = collect(cabin, axle * CFrame.new(Rides.cabinOffset(index, 0)))
	end
	wheels[model] = { model = model, axle = axle, rotor = collect(rotorModel, axle), cabins = cabins }
end

local function stepWheels(now: number, camera: Vector3)
	local angle = Rides.wheelAngle(now)
	for model, wheel in wheels do
		if not model.Parent then
			wheels[model] = nil
		elseif (wheel.axle.Position - camera).Magnitude < ANIMATE_DISTANCE then
			move(wheel.rotor, wheel.axle * CFrame.Angles(-angle, 0, 0))
			for index, cabin in wheel.cabins do
				move(cabin, wheel.axle * CFrame.new(Rides.cabinOffset(index, angle)))
			end
		end
	end
end

-- ===== Катание =====

type Ride = {
	kind: "train" | "wheel",
	wheel: Wheel?,
	cabin: number?,
	started: number,
	departed: boolean,
	exit: CFrame,
}
local ride: Ride? = nil
local blockedPad: BasePart? = nil -- круг, с которого только что сошли: пока не отойдёшь, не сядешь снова

local function rootAndHumanoid(): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?,
		character:FindFirstChildOfClass("Humanoid")
end

local function onPad(root: BasePart, pad: BasePart): boolean
	local offset = root.Position - pad.Position
	return Vector2.new(offset.X, offset.Z).Magnitude < PAD_RADIUS and offset.Y > -1 and offset.Y < 6
end

local function seatFrame(current: Ride, now: number): CFrame?
	if current.kind == "train" then
		local head = Rides.trainAt(now)
		return Rides.trackFrame(Rides.carAngle(head, PASSENGER_CAR)) * CFrame.new(0, 2.4 + SEAT_HEIGHT, 0)
	end
	local wheel = current.wheel
	if not wheel or not current.cabin then
		return nil
	end
	local center = wheel.axle * CFrame.new(Rides.cabinOffset(current.cabin, Rides.wheelAngle(now)))
	local seat = center.Position + Vector3.new(0, -Rides.WHEEL.cabinSize.Y / 2 + 0.4 + SEAT_HEIGHT, 0)
	-- Лицом к площади: ось колеса смотрит на неё.
	return CFrame.lookAt(seat, seat + wheel.axle.XVector)
end

local function finish(placeAtExit: boolean)
	local current = ride
	ride = nil
	local root, humanoid = rootAndHumanoid()
	if humanoid then
		humanoid.Sit = false
	end
	if current and root and placeAtExit then
		root.CFrame = current.exit
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function start(kind: "train" | "wheel", pad: BasePart, now: number, wheel: Wheel?)
	local _, humanoid = rootAndHumanoid()
	if not humanoid then
		return
	end
	local exit = CFrame.new(pad.Position + Vector3.new(0, 3, 0))
	local cabin = if wheel then Rides.lowestCabin(Rides.wheelAngle(now)) else nil
	ride = { kind = kind, wheel = wheel, cabin = cabin, started = now, departed = false, exit = exit }
	blockedPad = pad
	humanoid.Sit = true
end

local function wheelOf(pad: BasePart): Wheel?
	for model, wheel in wheels do
		if pad:IsDescendantOf(model) then
			return wheel
		end
	end
	return nil
end

local function stepRide(now: number)
	local root, humanoid = rootAndHumanoid()
	if not root or not humanoid or humanoid.Health <= 0 then
		if ride then
			ride = nil
		end
		return
	end

	local current = ride
	if current then
		-- Прыжок — сойти. Sit сбрасывает сам движок, когда ребёнок жмёт прыжок.
		if not humanoid.Sit then
			ride = nil
			return
		end
		if current.kind == "train" then
			local _, standing = Rides.trainAt(now)
			if not standing then
				current.departed = true
			elseif current.departed then
				finish(true) -- круг проехали, поезд снова у платформы
				return
			end
		elseif now - current.started >= Rides.WHEEL.period then
			finish(true)
			return
		end
		local seat = seatFrame(current, now)
		if seat then
			root.CFrame = seat
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		return
	end

	local _, standing = Rides.trainAt(now)
	for _, pad in CollectionService:GetTagged("AF_TrainBoard") do
		if pad:IsA("BasePart") then
			pad.Color = if standing then PAD_READY else PAD_WAIT
			if onPad(root, pad) then
				if pad ~= blockedPad and standing then
					start("train", pad, now, nil)
					return
				end
			elseif pad == blockedPad then
				blockedPad = nil
			end
		end
	end
	for _, pad in CollectionService:GetTagged("AF_WheelBoard") do
		if pad:IsA("BasePart") then
			pad.Color = PAD_READY
			local wheel = wheelOf(pad)
			if onPad(root, pad) then
				if pad ~= blockedPad and wheel then
					start("wheel", pad, now, wheel)
					return
				end
			elseif pad == blockedPad then
				blockedPad = nil
			end
		end
	end
end

-- Кто сейчас катается: для стенда проверки и для отладки.
function RideController.riding(): string?
	return if ride then ride.kind else nil
end

function RideController.init()
	local function watch(tag: string, attach: (Instance) -> ())
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
			-- Детали модели приходят вслед за ней: даём им доехать.
			task.delay(1, attach, instance)
		end)
		for _, instance in CollectionService:GetTagged(tag) do
			attach(instance)
		end
	end
	watch("AF_Train", attachTrain)
	watch("AF_Wheel", attachWheel)

	RunService:BindToRenderStep("AF_Rides", Enum.RenderPriority.Camera.Value - 1, function()
		local now = workspace:GetServerTimeNow()
		local camera = workspace.CurrentCamera
		stepTrain(now)
		stepWheels(now, if camera then camera.CFrame.Position else Vector3.zero)
		stepRide(now)
	end)
end

return RideController
