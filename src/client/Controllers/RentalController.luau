--!strict
--[[
	Прокат в парке глазами клиента (Config/Rental, Services/RentalService).

	Сервер приварил вещь к персонажу и поднял скорость — остальное здесь:
	  · поза своего персонажа: на самокате стоит, на велосипеде сидит,
	    с лошадкой бежит сам (стандартные анимации Roblox, как у танцев);
	  · у всех катающихся рядом крутятся колёса и педали, лошадка скачет —
	    по скорости корня, у каждого клиента своя картинка, сеть не тратится;
	  · кнопка со значком вещи и ✖ слева, над танцами: тап — слезть.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Rental = require(Shared.Config.Rental)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local AudioController = require(script.Parent.AudioController)

local RentalController = {}

local VEHICLE_TAG = "RentalVehicle"
local NEAR = 150

local player = Players.LocalPlayer
local pose: AnimationTrack? = nil
local button: TextButton? = nil
local angles: { [Motor6D]: number } = {}

local function ring(key: string)
	local id = AudioRegistry.ids[key]
	if not id or id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.6
	sound.SoundGroup = AudioController.group("SFX")
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

local function stopPose()
	if pose then
		pose:Stop(0.2)
		pose = nil
	end
end

local function playPose(vehicle: Rental.Vehicle)
	stopPose()
	local spec = (Rental.POSES :: any)[vehicle.pose]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not spec or not humanoid or not animator then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId =
		`rbxassetid://{if humanoid.RigType == Enum.HumanoidRigType.R6 then spec.r6 else spec.r15}`
	local track = animator:LoadAnimation(animation)
	-- Поверх бега: ноги не бегут, а стоят на деке или крутят педали.
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.2)
	pose = track
end

local function buildButton()
	local screen = Instance.new("ScreenGui")
	screen.Name = "AlphabetFallRental"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = player:WaitForChild("PlayerGui")

	local off = Instance.new("TextButton")
	off.Name = "RentalOff"
	off.Size = UDim2.fromScale(0.09, 0.11)
	off.Position = UDim2.fromScale(0.055, 0.44)
	off.AnchorPoint = Vector2.new(0, 0)
	off.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	off.Text = ""
	off.Visible = false
	off.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = off
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = off
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(240, 90, 100)
	stroke.Parent = off

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(0.8, 0.8)
	icon.Position = UDim2.fromScale(0.1, 0.1)
	icon.BackgroundTransparency = 1
	icon.TextScaled = true
	icon.Text = ""
	icon.Parent = off
	-- Красный крестик в углу: «слезть».
	local cross = Instance.new("TextLabel")
	cross.Name = "Cross"
	cross.Size = UDim2.fromScale(0.42, 0.42)
	cross.Position = UDim2.fromScale(0.62, -0.08)
	cross.BackgroundColor3 = Color3.fromRGB(240, 90, 100)
	cross.TextColor3 = Color3.new(1, 1, 1)
	cross.Font = Enum.Font.FredokaOne
	cross.TextScaled = true
	cross.Text = "✖"
	cross.Parent = off
	local crossCorner = Instance.new("UICorner")
	crossCorner.CornerRadius = UDim.new(0.5, 0)
	crossCorner.Parent = cross

	off.Activated:Connect(function()
		RemoteDefs.event("RentalOff"):FireServer()
	end)
	button = off
end

local function onRiding()
	local vehicle = Rental.get(player:GetAttribute("Riding"))
	local off = button
	if vehicle then
		if off then
			off.Visible = true
			local icon = off:FindFirstChild("Icon")
			if icon and icon:IsA("TextLabel") then
				icon.Text = vehicle.icon
			end
		end
		ring(vehicle.sound)
		-- Персонаж садится на вещь в тот же кадр: позу ставим, когда вещь уже пришла.
		task.delay(0.1, function()
			if player:GetAttribute("Riding") == vehicle.id then
				playPose(vehicle)
			end
		end)
	else
		if off then
			off.Visible = false
		end
		stopPose()
	end
end

-- Колёса, педали и скачущая лошадка у всех катающихся рядом.
local function animate(dt: number)
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local now = os.clock()
	for _, model in CollectionService:GetTagged(VEHICLE_TAG) do
		local character = model.Parent
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not model:IsA("Model") or (eye and (root.Position - eye).Magnitude > NEAR) then
			continue
		end
		-- Со знаком: назад колёса крутятся назад.
		local speed = root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector)
		for _, motor in model:GetDescendants() do
			if motor:IsA("Motor6D") and (motor.Name == "Axle" or motor.Name == "Crank") then
				local base = motor:GetAttribute("Base")
				local radius = motor:GetAttribute("Radius") or 1
				local ratio = motor:GetAttribute("Ratio") or 1
				if typeof(base) == "CFrame" then
					local angle = (angles[motor] or 0) - speed / radius * ratio * dt
					angles[motor] = angle % (math.pi * 2)
					motor.C0 = base * CFrame.Angles(angle, 0, 0)
				end
			end
		end
		if model:GetAttribute("Vehicle") == "unicorn" then
			local joint = model:FindFirstChild("RentalJoint", true)
			local base = joint and joint:GetAttribute("Base")
			if joint and joint:IsA("Motor6D") and typeof(base) == "CFrame" then
				local flat =
					Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
				local gallop = math.clamp(flat / 10, 0, 1)
				local beat = now * 9
				joint.C0 = base
					* CFrame.new(0, math.abs(math.sin(beat)) * Rental.GALLOP_BOB * gallop, 0)
					* CFrame.Angles(math.sin(beat) * 0.12 * gallop, 0, 0)
			end
		end
	end
	for motor in angles do
		if not motor.Parent then
			angles[motor] = nil
		end
	end
end

function RentalController.init()
	buildButton()
	player:GetAttributeChangedSignal("Riding"):Connect(onRiding)
	player.CharacterAdded:Connect(function()
		pose = nil
	end)
	onRiding()
	RunService.RenderStepped:Connect(animate)
end

return RentalController
