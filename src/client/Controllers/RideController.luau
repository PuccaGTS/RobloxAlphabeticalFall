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

-- ===== Карусель =====

type Carousel = { center: CFrame, rotor: Group, horses: { Group } }
local carousels: { [Instance]: Carousel } = {}

local attachCarousel: (Instance) -> ()
function attachCarousel(model: Instance)
	local center = model:GetAttribute("Center")
	local rotorModel = model:FindFirstChild("Rotor")
	if typeof(center) ~= "CFrame" or not rotorModel then
		return
	end
	local horses: { Group } = {}
	for index = 1, Rides.CAROUSEL.horses do
		local steed = model:FindFirstChild(`Horse_{index}`)
		if not steed then
			if model.Parent then
				task.delay(2, attachCarousel, model)
			end
			return
		end
		horses[index] = collect(steed, center * Rides.horseFrame(index, 0, 0))
	end
	carousels[model] = { center = center, rotor = collect(rotorModel, center), horses = horses }
end

-- ===== Лодочки-лебеди =====

type Swans = { center: CFrame, boats: { Group } }
local lakes: { [Instance]: Swans } = {}

local attachSwans: (Instance) -> ()
function attachSwans(model: Instance)
	local center = model:GetAttribute("Center")
	if typeof(center) ~= "CFrame" then
		return
	end
	local boats: { Group } = {}
	for index = 1, Rides.SWANS.boats do
		local boat = model:FindFirstChild(`Swan_{index}`)
		if not boat then
			if model.Parent then
				task.delay(2, attachSwans, model)
			end
			return
		end
		boats[index] = collect(boat, center * Rides.swanFrame(index, 0, 0))
	end
	lakes[model] = { center = center, boats = boats }
end

local function stepSwans(now: number, camera: Vector3)
	local angle = Rides.swanAngle(now)
	for model, lake in lakes do
		if not model.Parent then
			lakes[model] = nil
		elseif (lake.center.Position - camera).Magnitude < ANIMATE_DISTANCE then
			for index, boat in lake.boats do
				move(boat, lake.center * Rides.swanFrame(index, angle, now))
			end
		end
	end
end

-- Лодочка, которая сейчас ближе всех к мосткам.
local function nearestSwan(lake: Swans, pad: BasePart, now: number): number
	local angle = Rides.swanAngle(now)
	local best, bestDistance = 1, math.huge
	for index = 1, Rides.SWANS.boats do
		local distance = ((lake.center * Rides.swanFrame(index, angle, now)).Position - pad.Position).Magnitude
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

local function stepCarousels(now: number, camera: Vector3)
	local angle = Rides.carouselAngle(now)
	for model, carousel in carousels do
		if not model.Parent then
			carousels[model] = nil
		elseif (carousel.center.Position - camera).Magnitude < ANIMATE_DISTANCE then
			move(carousel.rotor, carousel.center * CFrame.Angles(0, -angle, 0))
			for index, steed in carousel.horses do
				move(steed, carousel.center * Rides.horseFrame(index, angle, now))
			end
		end
	end
end

-- ===== Воздушный шар =====

type Balloon = {
	home: CFrame,
	inward: Vector3,
	group: Group,
	flame: BasePart?,
	fire: Fire?,
	burning: boolean,
}
local balloons: { [Instance]: Balloon } = {}

local attachBalloon: (Instance) -> ()
function attachBalloon(model: Instance)
	local inward = model:GetAttribute("Inward")
	local body = model:FindFirstChild("Balloon")
	local home = body and body:GetAttribute("Home")
	if
		typeof(inward) ~= "Vector3"
		or typeof(home) ~= "CFrame"
		or not body
		or not body:FindFirstChild("Crown")
	then
		if model.Parent then
			task.delay(2, attachBalloon, model)
		end
		return
	end
	local flame = body:FindFirstChild("Flame") :: BasePart?
	balloons[model] = {
		home = home,
		inward = inward,
		group = collect(body, home),
		flame = flame,
		fire = if flame then flame:FindFirstChildOfClass("Fire") else nil,
		burning = false,
	}
end

-- Короткий звук в точке мира: свисток горки, горелка шара.
local function playAt(key: string, at: BasePart?, volume: number, reach: number)
	local id = AudioRegistry.ids[key]
	if not at or not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMaxDistance = reach
	sound.RollOffMinDistance = 15
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = at
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function balloonFrame(balloon: Balloon, now: number): (CFrame, boolean, boolean)
	local offset, standing, burning = Rides.balloonAt(now, balloon.inward)
	-- В полёте шар чуть покачивается: он висит на ветру, а не едет по рельсу.
	local sway = if standing
		then CFrame.identity
		else CFrame.Angles(math.sin(now * 0.7) * 0.03, 0, math.cos(now * 0.5) * 0.03)
	return (balloon.home + offset) * sway, standing, burning
end

local function stepBalloons(now: number)
	for model, balloon in balloons do
		if not model.Parent then
			balloons[model] = nil
			continue
		end
		local frame, _, burning = balloonFrame(balloon, now)
		move(balloon.group, frame)
		if burning ~= balloon.burning then
			balloon.burning = burning
			if balloon.flame then
				balloon.flame.Transparency = if burning then 0.25 else 1
			end
			if balloon.fire then
				balloon.fire.Enabled = burning
			end
			if burning then
				playAt("sfx_balloon_burner", balloon.flame, 0.7, 260)
			end
		end
	end
end

-- ===== Корабль-качели =====

type Ship = { pivot: CFrame, group: Group, hull: BasePart?, creak: Sound?, wasStanding: boolean? }
local ships: { [Instance]: Ship } = {}

local attachShip: (Instance) -> ()
function attachShip(model: Instance)
	local pivot = model:GetAttribute("Pivot")
	local swing = model:FindFirstChild("Ship")
	local hull = swing and swing:FindFirstChild("Hull")
	if typeof(pivot) ~= "CFrame" or not swing or not hull then
		if model.Parent then
			task.delay(2, attachShip, model)
		end
		return
	end
	local creak = hull:FindFirstChild("Creak")
	local id = AudioRegistry.ids.amb_ship_creak
	if creak and creak:IsA("Sound") and id and id ~= "" then
		creak.SoundId = id
		creak.SoundGroup = AudioController.group("SFX")
		creak.Volume = 0
	end
	ships[model] = {
		pivot = pivot,
		group = collect(swing, pivot),
		hull = hull :: BasePart,
		creak = if creak and creak:IsA("Sound") then creak else nil,
	}
end

local function stepShips(now: number, camera: Vector3)
	local angle, standing, envelope = Rides.shipAt(now)
	for model, current in ships do
		if not model.Parent then
			ships[model] = nil
		elseif (current.pivot.Position - camera).Magnitude < ANIMATE_DISTANCE then
			move(current.group, current.pivot * CFrame.Angles(0, 0, angle))
			-- Скрип тем громче, чем выше раскачка; на стоянке тихо.
			local creak = current.creak
			if creak and creak.SoundId ~= "" then
				creak.Volume = 0.45 * envelope
				if envelope > 0.05 and not creak.IsPlaying then
					creak:Play()
				elseif envelope <= 0.05 and creak.IsPlaying then
					creak:Stop()
				end
			end
			if current.wasStanding == true and not standing then
				playAt("sfx_seagulls", current.hull, 0.6, 120) -- отплыли: кричат чайки
			end
			current.wasStanding = standing
		end
	end
end

-- ===== Катание =====

type Kind = "train" | "wheel" | "carousel" | "slide" | "balloon" | "swan" | "ship"
type Ride = {
	kind: Kind,
	wheel: Wheel?,
	cabin: number?,
	carousel: Carousel?,
	horse: number?,
	lake: Swans?,
	boat: number?,
	slide: CFrame?, -- опорная точка горки
	balloon: Balloon?,
	ship: Ship?,
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
	if current.kind == "ship" then
		local boat = current.ship
		if not boat then
			return nil
		end
		local spec = Rides.SHIP
		local deck = boat.pivot * Rides.shipFrame((Rides.shipAt(now)))
		local lift = 0.85 + SEAT_HEIGHT - 0.3
		-- Лицом к середине корабля: с кормы видна вся палуба и небо на взмахе.
		local seat = deck * CFrame.new(spec.benches[spec.riderBench], lift, 0)
		return CFrame.lookAt(seat.Position, (deck * CFrame.new(0, lift, 0)).Position, deck.UpVector)
	elseif current.kind == "swan" then
		local lake = current.lake
		if not lake or not current.boat then
			return nil
		end
		local frame = lake.center * Rides.swanFrame(current.boat, Rides.swanAngle(now), now)
		return frame * CFrame.new(0, 1.4 + SEAT_HEIGHT - 0.3, 0.9)
	elseif current.kind == "carousel" then
		local carousel = current.carousel
		if not carousel or not current.horse then
			return nil
		end
		local frame = carousel.center * Rides.horseFrame(current.horse, Rides.carouselAngle(now), now)
		return frame * CFrame.new(0, 1.1 + SEAT_HEIGHT - 0.3, 0.1)
	elseif current.kind == "slide" then
		local base = current.slide
		if not base then
			return nil
		end
		local u = Rides.slideProgress(now - current.started)
		local here = (base * CFrame.new(Rides.slidePoint(u))).Position + Vector3.new(0, SEAT_HEIGHT, 0)
		local ahead = (base * CFrame.new(Rides.slidePoint(u + 0.01))).Position
			+ Vector3.new(0, SEAT_HEIGHT, 0)
		return CFrame.lookAt(here, ahead)
	elseif current.kind == "balloon" then
		local balloon = current.balloon
		if not balloon then
			return nil
		end
		local frame = balloonFrame(balloon, now)
		-- Лицом к площади: оттуда виден весь парк.
		local seat = (frame * CFrame.new(0, 0.4 + SEAT_HEIGHT, 0)).Position
		return CFrame.lookAt(seat, seat + balloon.inward)
	end
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

local function start(kind: Kind, pad: BasePart, now: number, wheel: Wheel?): Ride?
	local _, humanoid = rootAndHumanoid()
	if not humanoid then
		return nil
	end
	local exit = CFrame.new(pad.Position + Vector3.new(0, 3, 0))
	local cabin = if wheel then Rides.lowestCabin(Rides.wheelAngle(now)) else nil
	local current: Ride =
		{ kind = kind, wheel = wheel, cabin = cabin, started = now, departed = false, exit = exit }
	ride = current
	blockedPad = pad
	humanoid.Sit = true
	return current
end

-- Лошадка, которая сейчас ближе всех к кругу посадки.
local function nearestHorse(carousel: Carousel, pad: BasePart, now: number): number
	local angle = Rides.carouselAngle(now)
	local best, bestDistance = 1, math.huge
	for index = 1, Rides.CAROUSEL.horses do
		local position = (carousel.center * Rides.horseFrame(index, angle, now)).Position
		local distance = (position - pad.Position).Magnitude
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

-- Внизу горки вылетаешь из жёлоба вперёд, на траву.
local function leaveSlide(base: CFrame, root: BasePart, humanoid: Humanoid)
	local bottom = (base * CFrame.new(Rides.slidePoint(1))).Position
	local before = (base * CFrame.new(Rides.slidePoint(0.97))).Position
	local ahead = ((bottom - before) * Vector3.new(1, 0, 1)).Unit
	ride = nil
	humanoid.Sit = false
	local at = bottom + Vector3.new(0, 3, 0)
	root.CFrame = CFrame.lookAt(at, at + ahead)
	--[[
		Персонаж гасит свою скорость сам — и вставая, и в воздухе без нажатых
		клавиш: простой толчок пропадает за кадр. Поэтому треть секунды его несёт
		LinearVelocity, а дальше он летит сам и приземляется на коврик.
	]]
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local fling = Instance.new("LinearVelocity")
	fling.Attachment0 = attachment
	fling.MaxForce = 1e6
	fling.VectorVelocity = ahead * 24 + Vector3.new(0, 14, 0)
	fling.Parent = root
	task.delay(0.35, function()
		fling:Destroy()
		attachment:Destroy()
	end)
end

-- Круг посадки: светится зелёным, когда сесть можно, и сажает, если встал.
local function checkPads(
	tag: string,
	root: BasePart,
	ready: (BasePart) -> boolean,
	board: (BasePart) -> ()
): boolean
	for _, pad in CollectionService:GetTagged(tag) do
		if pad:IsA("BasePart") then
			local canBoard = ready(pad)
			pad.Color = if canBoard then PAD_READY else PAD_WAIT
			if onPad(root, pad) then
				if pad ~= blockedPad and canBoard then
					board(pad)
					return true
				end
			elseif pad == blockedPad then
				blockedPad = nil
			end
		end
	end
	return false
end

local function ownerOf(pad: BasePart, list: { [Instance]: any }): any
	for model, value in list do
		if pad:IsDescendantOf(model) then
			return value
		end
	end
	return nil
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
		elseif current.kind == "balloon" then
			local balloon = current.balloon
			local _, grounded = Rides.balloonAt(now, if balloon then balloon.inward else Vector3.xAxis)
			if not grounded then
				current.departed = true
			elseif current.departed then
				finish(true) -- облетели парк и сели на ту же лужайку
				return
			end
		elseif current.kind == "ship" then
			local _, standing = Rides.shipAt(now)
			if not standing then
				current.departed = true
			elseif current.departed then
				finish(true) -- раскачка кончилась, корабль снова у посадки
				return
			end
		elseif current.kind == "swan" then
			-- Круг по озеру — и обратно на мостки.
			if now - current.started >= Rides.SWANS.period then
				finish(true)
				return
			end
		elseif current.kind == "carousel" then
			if now - current.started >= Rides.CAROUSEL.period * Rides.CAROUSEL.laps then
				finish(true)
				return
			end
		elseif current.kind == "slide" then
			if now - current.started >= Rides.SLIDE.seconds then
				leaveSlide(current.slide :: CFrame, root, humanoid)
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
	local boarded = checkPads("AF_CarouselBoard", root, function(pad)
		return ownerOf(pad, carousels) ~= nil
	end, function(pad)
		local carousel = ownerOf(pad, carousels)
		local started = start("carousel", pad, now, nil)
		if started then
			started.carousel = carousel
			started.horse = nearestHorse(carousel, pad, now)
		end
	end) or checkPads("AF_SwanBoard", root, function(pad)
		return ownerOf(pad, lakes) ~= nil
	end, function(pad)
		local lake = ownerOf(pad, lakes)
		local started = start("swan", pad, now, nil)
		if started then
			started.lake = lake
			started.boat = nearestSwan(lake, pad, now)
		end
	end) or checkPads("AF_SlideBoard", root, function(pad)
		return pad.Parent ~= nil and typeof(pad.Parent:GetAttribute("Base")) == "CFrame"
	end, function(pad)
		local started = start("slide", pad, now, nil)
		if started then
			started.slide = (pad.Parent :: Instance):GetAttribute("Base")
			playAt("sfx_slide_whistle", pad, 0.9, 120)
		end
	end) or checkPads("AF_ShipBoard", root, function(pad)
		return ownerOf(pad, ships) ~= nil and select(2, Rides.shipAt(now))
	end, function(pad)
		local started = start("ship", pad, now, nil)
		if started then
			started.ship = ownerOf(pad, ships)
		end
	end) or checkPads("AF_BalloonBoard", root, function(pad)
		local balloon = ownerOf(pad, balloons)
		return balloon ~= nil and select(2, Rides.balloonAt(now, balloon.inward))
	end, function(pad)
		local started = start("balloon", pad, now, nil)
		if started then
			started.balloon = ownerOf(pad, balloons)
		end
	end)
	if boarded then
		return
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
	watch("AF_Carousel", attachCarousel)
	watch("AF_Swans", attachSwans)
	watch("AF_Balloon", attachBalloon)
	watch("AF_Ship", attachShip)

	RunService:BindToRenderStep("AF_Rides", Enum.RenderPriority.Camera.Value - 1, function()
		local now = workspace:GetServerTimeNow()
		local camera = workspace.CurrentCamera
		stepTrain(now)
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		stepWheels(now, eye)
		stepCarousels(now, eye)
		stepSwans(now, eye)
		stepBalloons(now)
		stepShips(now, eye)
		stepRide(now)
	end)
end

return RideController
