--!nonstrict
--[[
	Крышки сундуков в парке. Сундуки общие (Services/ChestService), а открыт
	каждый у ребёнка свой: крышку поднимаем локально, по своему инвентарю.
	Вещь сундука у ребёнка — крышка откинута и внутри пусто; нет — закрыт
	и заперт золотым замком.

	Меняем CFrame закреплённой детали на клиенте: другие игроки видят сундук
	таким, какой он у них самих.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Chests = require(Shared.Config.Chests)

local ChestController = {}

local OPEN_ANGLE = math.rad(-110)

local inventory: { string } = {}
local waiting = false

local function apply(model: Instance, animate: boolean)
	local lid = model:FindFirstChild("Lid")
	local hinge = lid and lid:GetAttribute("Hinge")
	local chest = Chests.get(model.Name)
	if not lid or not lid:IsA("BasePart") or typeof(hinge) ~= "CFrame" or not chest then
		return
	end

	if lid:GetAttribute("Closed") == nil then
		lid:SetAttribute("Closed", lid.CFrame)
	end
	local closed = lid:GetAttribute("Closed") :: CFrame

	local opened = Chests.isOpened(chest, inventory)
	local goal = if opened then hinge * CFrame.Angles(OPEN_ANGLE, 0, 0) * hinge:Inverse() * closed else closed
	if animate then
		TweenService:Create(lid, TweenInfo.new(0.6, Enum.EasingStyle.Back), { CFrame = goal }):Play()
	else
		lid.CFrame = goal
	end

	local lock = model:FindFirstChild("Lock")
	if lock and lock:IsA("BasePart") then
		lock.Transparency = if opened then 1 else 0
	end
end

local hooked: Instance? = nil

local function applyAll(animate: boolean)
	local folder = workspace:FindFirstChild("Chests")
	--[[
		В месте включена потоковая загрузка: сундук в парке приезжает к клиенту,
		только когда ребёнок подойдёт. Крышку ставим в момент, когда она появилась,
		а не только при смене инвентаря.
	]]
	if folder and hooked ~= folder then
		hooked = folder
		folder.DescendantAdded:Connect(function(descendant: Instance)
			if descendant.Name == "Lid" and descendant.Parent then
				task.defer(apply, descendant.Parent, false)
			end
		end)
	end
	if not folder then
		if not waiting then
			waiting = true
			task.spawn(function()
				local found = workspace:WaitForChild("Chests", 60)
				waiting = false
				if found then
					applyAll(false)
				end
			end)
		end
		return
	end
	for _, model in folder:GetChildren() do
		apply(model, animate)
	end
end

function ChestController.update(snapshot: any)
	if typeof(snapshot) ~= "table" or typeof(snapshot.inventory) ~= "table" then
		return
	end
	local before = #inventory
	inventory = snapshot.inventory
	-- Новая вещь — возможно, из сундука: крышку откидываем плавно, чтобы это увидели.
	applyAll(before > 0 and #inventory > before)
end

return ChestController
