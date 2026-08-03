--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Migrations = require(Shared.Logic.Migrations)
local ProfileTemplate = require(Shared.Config.ProfileTemplate)

local NOW = 1_700_000_000

return function()
	describe("Migrations.apply", function()
		it("применяет шаги последовательно до целевой версии", function()
			local trace = {}
			local steps = {
				[1] = function(profile)
					table.insert(trace, 1)
					profile.a = true
				end,
				[2] = function(profile)
					table.insert(trace, 2)
					profile.b = true
				end,
			}

			local profile, applied = Migrations.apply({ version = 1 }, 3, steps)

			expect(profile.version).to.equal(3)
			expect(applied).to.equal(2)
			expect(profile.a).to.equal(true)
			expect(profile.b).to.equal(true)
			expect(trace[1]).to.equal(1)
			expect(trace[2]).to.equal(2)
		end)

		it("ничего не делает, если версия уже целевая", function()
			local _, applied = Migrations.apply({ version = 3 }, 3, {})
			expect(applied).to.equal(0)
		end)

		it("считает профиль без версии первой версией", function()
			local profile = Migrations.apply({}, 2, {})
			expect(profile.version).to.equal(2)
		end)

		it("переживает падение шага и не застревает на версии", function()
			local steps = {
				[1] = function()
					error("шаг сломан")
				end,
			}

			local profile = Migrations.apply({ version = 1 }, 2, steps)
			expect(profile.version).to.equal(2)
		end)

		it("не трогает нетабличные данные", function()
			local result, applied = Migrations.apply("мусор", 5, {})
			expect(result).to.equal("мусор")
			expect(applied).to.equal(0)
		end)
	end)

	describe("Migrations.fillDefaults", function()
		it("достраивает отсутствующие поля верхнего уровня", function()
			local profile = Migrations.fillDefaults({ version = 1, stars = 40 }, NOW)

			expect(profile.stars).to.equal(40)
			expect(profile.level).to.equal(1)
			expect(typeof(profile.letters)).to.equal("table")
			expect(typeof(profile.settings)).to.equal("table")
		end)

		it("достраивает отсутствующие поля настроек, не сбрасывая заданные", function()
			local profile = Migrations.fillDefaults({ settings = { music = 0.1 } }, NOW)

			expect(profile.settings.music).to.equal(0.1)
			expect(profile.settings.echoMode).to.equal("A")
			expect(profile.settings.subtitles).to.equal(false)
		end)

		it("сбрасывает поля с неверным типом", function()
			local profile = Migrations.fillDefaults({ stars = "много", inventory = 5 }, NOW)

			expect(profile.stars).to.equal(0)
			expect(typeof(profile.inventory)).to.equal("table")
		end)

		it("из мусора делает чистый профиль", function()
			local profile = Migrations.fillDefaults(nil, NOW)
			expect(profile.version).to.equal(ProfileTemplate.VERSION)
			expect(profile.stars).to.equal(0)
		end)

		it("режим эха по умолчанию — без микрофона", function()
			local profile = Migrations.fillDefaults({}, NOW)
			expect(profile.settings.echoMode).to.equal("A")
			expect(profile.parent.echoConsent).to.equal(false)
		end)
	end)

	describe("ProfileTemplate.toSnapshot", function()
		it("отдаёт клиенту статусы букв, но не внутреннюю статистику", function()
			local profile = ProfileTemplate.new(NOW)
			profile.letters.m = {
				mastery = 2,
				correct = 7,
				wrong = 3,
				streak = 2,
				types = { "letter_rain" },
				lastSeen = NOW,
				reviewStep = 2,
				nextReview = NOW + 100,
				avgReactionMs = 1234,
				answers = 7,
			}

			local snapshot = ProfileTemplate.toSnapshot(profile)

			expect(snapshot.mastery.m).to.equal(2)
			expect(snapshot.nextReview.m).to.equal(NOW + 100)
			expect(snapshot.letters).to.equal(nil)
		end)

		it("не отдаёт клиенту родительский PIN и лимиты", function()
			local profile = ProfileTemplate.new(NOW)
			profile.parent.pinHash = "секрет"
			profile.parent.dailyLimitMin = 20

			local snapshot = ProfileTemplate.toSnapshot(profile)

			expect(snapshot.parent).to.equal(nil)
			expect(snapshot.echoConsent).to.equal(false)
		end)

		it("копирует таблицы, а не отдаёт ссылки на профиль", function()
			local profile = ProfileTemplate.new(NOW)
			table.insert(profile.inventory, "hat_stargazer")

			local snapshot = ProfileTemplate.toSnapshot(profile)
			table.insert(snapshot.inventory, "взлом")

			expect(#profile.inventory).to.equal(1)
		end)
	end)
end
