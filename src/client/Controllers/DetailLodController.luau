--!nonstrict
--[[
	Мелкие детали чужих участков издалека не рисуются.

	Замер в настоящем Play (tools/playtest/scenarios/perf.luau): на площади
	с застроенными участками в кадре было больше 600 тысяч треугольников,
	и половину давали шарики дворов — глазки зверят, цветы в ящиках, лампочки
	гирлянды, яблоки. Шар в Roblox рисуется сотней с лишним треугольников,
	а на участке таких сотня. С соседнего участка их не разглядеть, а дешёвый
	планшет (docs/07-TECH-ARCH.md § 8) платит за каждый.

	Сервер помечает мелкие шарики тегом PlotDetail (BaseService). Здесь участок
	дальше HIDE_DISTANCE от камеры прячет их через LocalTransparencyModifier —
	только у этого клиента: свой двор вблизи всегда в полной красе. Порог с запасом
	(SHOW_DISTANCE ближе), чтобы детали не мигали на границе.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Base = require(Shared.Config.Base)

local DetailLodController = {}

DetailLodController.TAG = "PlotDetail"
DetailLodController.HIDE_DISTANCE = 95
DetailLodController.SHOW_DISTANCE = 85
local CHECK_EVERY = 0.4

local far: { [number]: boolean } = {}

local function plotIndexOf(instance: Instance): number?
	local node = instance.Parent
	while node and node ~= workspace do
		local index = string.match(node.Name, "^Plot_(%d+)$")
		if index then
			return tonumber(index)
		end
		node = node.Parent
	end
	return nil
end

local function apply(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local index = plotIndexOf(part)
	if index then
		part.LocalTransparencyModifier = if far[index] then 1 else 0
	end
end

-- Далеко ли участок: по расстоянию от камеры до его центра, с запасом против мигания.
function DetailLodController.isFar(distance: number, wasFar: boolean): boolean
	return if wasFar
		then distance > DetailLodController.SHOW_DISTANCE
		else distance > DetailLodController.HIDE_DISTANCE
end

function DetailLodController.init()
	-- Детали, приехавшие со стримингом или после перестройки участка, сразу в нужном виде.
	CollectionService:GetInstanceAddedSignal(DetailLodController.TAG):Connect(apply)

	task.spawn(function()
		while true do
			local camera = workspace.CurrentCamera
			local plots = workspace:FindFirstChild("Plots")
			if camera and plots then
				local eye = camera.CFrame.Position
				for index = 1, Base.PLOT_COUNT do
					local center = Base.plotPosition(index)
					local distance = (Vector3.new(center.X, eye.Y, center.Z) - eye).Magnitude
					local nowFar = DetailLodController.isFar(distance, far[index] == true)
					if nowFar ~= (far[index] == true) then
						far[index] = nowFar
						local model = plots:FindFirstChild(`Plot_{index}`)
						if model then
							for _, descendant in model:GetDescendants() do
								if CollectionService:HasTag(descendant, DetailLodController.TAG) then
									apply(descendant)
								end
							end
						end
					end
				end
			end
			task.wait(CHECK_EVERY)
		end
	end)
end

return DetailLodController
