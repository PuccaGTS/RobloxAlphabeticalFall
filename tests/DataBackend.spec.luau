--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataBackend = require(ReplicatedStorage.SourceServices.DataBackend)

return function()
	describe("DataBackend: удаление по запросу", function()
		it(
			"у обоих бэкендов есть удаление — контракт Backend полный",
			function()
				local memory = DataBackend.newMemory()
				expect(typeof(memory.removeAsync)).to.equal("function")
				local ok, store = pcall(DataBackend.newDataStore, "Probe", "dev")
				if ok then
					expect(typeof(store.removeAsync)).to.equal("function")
				end
			end
		)

		it("удалённый профиль больше не загружается", function()
			local memory = DataBackend.newMemory()
			memory:saveAsync("player_1", { stars = 5 }, false)
			memory:saveAsync("player_2", { stars = 7 }, false)

			local removed, err, busy = memory:removeAsync("player_1", false)
			expect(removed).to.equal(true)
			expect(err).to.equal(nil)
			expect(busy).to.equal(false)

			expect(memory:loadAsync("player_1")).to.equal(nil)
			expect(memory:loadAsync("player_2").stars).to.equal(7)
		end)

		it("удаление несуществующего ключа — не ошибка", function()
			local memory = DataBackend.newMemory()
			expect(memory:removeAsync("player_404", false)).to.equal(true)
		end)
	end)
end
