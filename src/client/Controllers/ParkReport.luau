--!nonstrict
--[[
	«В парке сделано дело»: сел на шар, дошёл по азбуке до Я, позвонил в кристалл.
	Само дело живёт на клиенте (PlaygroundController, RideController, SkateController),
	а задание дня про уголок парка засчитывает сервер (Services/QuestService,
	событие ParkDone) — он же проверяет, что ребёнок стоит у этого места.

	Одно и то же место сообщается не чаще раза в полминуты: катающийся по кругу
	не засыпает сервер одинаковыми событиями.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteDefs = require(ReplicatedStorage:WaitForChild("Shared").Net.RemoteDefs)

local ParkReport = {}

local EVERY = 30

local sent: { [string]: number } = {}

function ParkReport.done(spotId: string?)
	if not spotId then
		return
	end
	local now = os.clock()
	if (sent[spotId] or -math.huge) + EVERY > now then
		return
	end
	sent[spotId] = now
	RemoteDefs.event("ParkDone"):FireServer(spotId)
end

-- Место парка, которому принадлежит деталь: модели мест зовутся Play_<id>.
function ParkReport.spotOf(part: Instance): string?
	local node: Instance? = part
	while node do
		if node:IsA("Model") and string.sub(node.Name, 1, 5) == "Play_" then
			return string.sub(node.Name, 6)
		end
		node = node.Parent
	end
	return nil
end

return ParkReport
