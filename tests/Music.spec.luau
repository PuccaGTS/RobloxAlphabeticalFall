--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Music = require(Shared.Config.Music)
local Ambient = require(Shared.Config.Ambient)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local Decor = require(Shared.Config.Decor)

return function()
	describe("Config: музыка и звуки природы", function()
		it(
			"звуковая зона: звучит ближайшая, у края и снаружи — ни одной",
			function()
				local zones = {
					{ position = Vector3.new(0, 0, 0), radius = 60 },
					{ position = Vector3.new(70, 0, 0), radius = 60 },
				}
				expect(Ambient.zoneAt(Vector3.new(10, 5, 0), zones)).to.equal(1)
				expect(Ambient.zoneAt(Vector3.new(60, 0, 0), zones)).to.equal(2)
				-- Посередине обе задевают, но слышна одна — та, к которой ближе.
				expect(Ambient.zoneAt(Vector3.new(34, 0, 0), zones)).to.equal(1)
				expect(Ambient.zoneAt(Vector3.new(0, 0, 50), zones)).to.equal(nil)
				expect(Ambient.zoneAt(Vector3.new(0, 0, 0), {})).to.equal(nil)
			end
		)

		it("у каждого места с музыкой — своя зона", function()
			for _, spot in { Ambient.CAROUSEL, Ambient.WINTER, Ambient.SWANS, Ambient.SHIP, Ambient.GALLERY } do
				expect(spot.zone).to.equal(true)
			end
		end)

		it("каждый ключ плейлиста заведён в реестре", function()
			for place, list in Music.PLAYLISTS do
				for _, key in list do
					expect(AudioRegistry.ids[key] ~= nil).to.equal(true)
				end
				expect(#list > 0).to.equal(true)
			end
		end)

		it(
			"у каждого места есть хотя бы один трек с id — игра не молчит",
			function()
				for place, list in Music.PLAYLISTS do
					local playable = 0
					for _, key in list do
						if AudioRegistry.ids[key] ~= "" then
							playable += 1
						end
					end
					expect(playable > 0).to.equal(true)
				end
			end
		)

		it("библиотечные треки описаны и у всех есть id", function()
			for _, track in Music.LIBRARY do
				expect(string.match(AudioRegistry.ids[track.key] or "", "^rbxassetid://%d+$") ~= nil).to.equal(
					true
				)
			end
		end)

		it("забеги ведут в существующие плейлисты", function()
			for _, place in Music.RUN_PLACE do
				expect(Music.PLAYLISTS[place] ~= nil).to.equal(true)
			end
			expect(Music.PLAYLISTS.hub ~= nil).to.equal(true)
		end)

		it(
			"библиотечный звук не считается репликой и не съедает потолок озвучки",
			function()
				for _, key in AudioRegistry.requiredKeys() do
					expect(string.sub(key, 1, 8) == "mus_lib_").to.equal(false)
					expect(string.sub(key, 1, 4) == "amb_").to.equal(false)
				end
			end
		)

		it(
			"звуки природы есть в реестре, звучащие места — в каталоге декора",
			function()
				expect(AudioRegistry.ids[Ambient.BED.key] ~= "").to.equal(true)
				for decorId, spot in Ambient.SPOTS do
					expect(Decor.get(decorId) ~= nil).to.equal(true)
					expect(AudioRegistry.ids[spot.key] ~= "").to.equal(true)
					expect(spot.radius > 0).to.equal(true)
				end
			end
		)
	end)
end
