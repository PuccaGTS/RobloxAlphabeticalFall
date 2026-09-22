--!nocheck
-- Поющий фонтан: дождаться шоу по серверным часам и снять волну, «чёт-нечет» и финал.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(player, note)
	local Fountain = require(ReplicatedStorage.Shared.Config.Fountain)
	task.wait(8)
	local eye =
		CFrame.lookAt(Fountain.CENTER + Vector3.new(20, 6, 16), Fountain.CENTER + Vector3.new(0, 10, 0))
	-- Снимок уходит через ~4 с после команды: целимся заранее.
	for _, moment in { 1, 9.5, 21.5 } do
		while true do
			local t = workspace:GetServerTimeNow() % Fountain.EVERY
			local wanted = moment - 4
			local wait = (wanted - t) % Fountain.EVERY
			if wait < 0.3 or wait > Fountain.EVERY - 1 then
				break
			end
			task.wait(math.min(wait, 5))
		end
		_G.ZZ_Shot(player, `fountain_{math.floor(moment)}`, eye, 60)
		note(string.format("shot at show time %.1f", (workspace:GetServerTimeNow() % Fountain.EVERY)))
	end
end
