--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Migrations = require(Shared.Logic.Migrations)
local ProfileTemplate = require(Shared.Config.ProfileTemplate)
local Base = require(Shared.Config.Base)
local Levels = require(Shared.Config.Levels)

local NOW = 1_700_000_000

return function()
	describe("Migrations.apply", function()
		it(
			"применяет шаги последовательно до целевой версии",
			function()
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
			end
		)

		it("ничего не делает, если версия уже целевая", function()
			local _, applied = Migrations.apply({ version = 3 }, 3, {})
			expect(applied).to.equal(0)
		end)

		it("считает профиль без версии первой версией", function()
			local profile = Migrations.apply({}, 2, {})
			expect(profile.version).to.equal(2)
		end)

		it(
			"переживает падение шага и не застревает на версии",
			function()
				local steps = {
					[1] = function()
						error("шаг сломан")
					end,
				}

				local profile = Migrations.apply({ version = 1 }, 2, steps)
				expect(profile.version).to.equal(2)
			end
		)

		it("не трогает нетабличные данные", function()
			local result, applied = Migrations.apply("мусор", 5, {})
			expect(result).to.equal("мусор")
			expect(applied).to.equal(0)
		end)
	end)

	describe("Migrations.fillDefaults", function()
		it(
			"достраивает отсутствующие поля верхнего уровня",
			function()
				local profile = Migrations.fillDefaults({ version = 1, stars = 40 }, NOW)

				expect(profile.stars).to.equal(40)
				expect(profile.level).to.equal(1)
				expect(typeof(profile.letters)).to.equal("table")
				expect(typeof(profile.settings)).to.equal("table")
			end
		)

		it(
			"достраивает отсутствующие поля настроек, не сбрасывая заданные",
			function()
				local profile = Migrations.fillDefaults({ settings = { music = 0.1 } }, NOW)

				expect(profile.settings.music).to.equal(0.1)
				expect(profile.settings.voice).to.equal(1)
				expect(profile.settings.subtitles).to.equal(false)
			end
		)

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

		it(
			"первая ступень алфавита открыта в любом профиле",
			function()
				local profile = Migrations.fillDefaults({}, NOW)
				expect(profile.stages[1].unlocked).to.equal(true)
			end
		)

		it(
			"у профиля без забегов появляется пустая таблица забегов",
			function()
				local profile = Migrations.fillDefaults({}, NOW)
				expect(typeof(profile.runs)).to.equal("table")
				expect(next(profile.runs)).to.equal(nil)
			end
		)
	end)

	describe("ProfileTemplate.toSnapshot", function()
		it(
			"отдаёт клиенту статусы букв, но не внутреннюю статистику",
			function()
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
			end
		)

		it("не отдаёт клиенту родительский PIN и лимиты", function()
			local profile = ProfileTemplate.new(NOW)
			profile.parent.pinHash = "секрет"
			profile.parent.dailyLimitMin = 20

			local snapshot = ProfileTemplate.toSnapshot(profile)

			expect(snapshot.parent).to.equal(nil)
			expect(snapshot.settings.hideRobux).to.equal(false)
		end)

		it(
			"копирует таблицы, а не отдаёт ссылки на профиль",
			function()
				local profile = ProfileTemplate.new(NOW)
				table.insert(profile.inventory, "hat_stargazer")

				local snapshot = ProfileTemplate.toSnapshot(profile)
				table.insert(snapshot.inventory, "взлом")

				expect(#profile.inventory).to.equal(1)
			end
		)
	end)

	--[[
		Шаг 1 — переход игры со звуков на алфавит. Проверяем главное: выученные буквы
		переживают миграцию. Всё остальное можно потерять, буквы — нет.
	]]
	describe("Миграция 1 → 2: буквы вместо звуков", function()
		local function legacyProfile()
			return {
				version = 1,
				letters = {
					m = { mastery = 3, correct = 9, wrong = 1, streak = 4, types = { "letter_rain" } },
				},
				syllables = { ma = true, mu = true },
				words = { mama = true },
				islands = {
					[1] = { unlocked = true, bossDone = true, chests = { "chest_1" } },
					[2] = { unlocked = true, bossDone = false, chests = {} },
				},
				settings = { music = 0.4, echoMode = "B" },
				parent = { echoConsent = true },
			}
		end

		it("прогресс по буквам сохраняется целиком", function()
			local profile = Migrations.normalize(legacyProfile(), NOW)

			expect(profile.letters.m.mastery).to.equal(3)
			expect(profile.letters.m.correct).to.equal(9)
		end)

		it("слоги и слова уходят из профиля", function()
			local profile = Migrations.normalize(legacyProfile(), NOW)

			expect(profile.syllables).to.equal(nil)
			expect(profile.words).to.equal(nil)
		end)

		it(
			"острова становятся ступенями и не теряют открытость",
			function()
				local profile = Migrations.normalize(legacyProfile(), NOW)

				expect(profile.islands).to.equal(nil)
				expect(profile.stages[1].unlocked).to.equal(true)
				expect(profile.stages[2].unlocked).to.equal(true)
			end
		)

		it("режим эха уезжает вместе с испытанием", function()
			local profile = Migrations.normalize(legacyProfile(), NOW)

			expect(profile.settings.echoMode).to.equal(nil)
			expect(profile.parent.echoConsent).to.equal(nil)
			expect(profile.settings.music).to.equal(0.4)
		end)

		it(
			"профиль без островов не падает и получает первую ступень",
			function()
				local profile = Migrations.normalize({ version = 1 }, NOW)

				expect(profile.version).to.equal(ProfileTemplate.VERSION)
				expect(profile.stages[1].unlocked).to.equal(true)
			end
		)
	end)

	--[[
		Шаг 2 — сохранка забега переехала в профиль. Проверяем, что старый профиль
		её получает пустой, а мёртвое поле ступени уходит.
	]]
	describe("Миграция 2 → 3: сохранка в профиле", function()
		local function version2Profile()
			return {
				version = 2,
				letters = { m = { mastery = 2, correct = 4, wrong = 1, streak = 2, types = {} } },
				stages = {
					[1] = { unlocked = true, checkpoint = 0, chests = {} },
					[2] = { unlocked = true, checkpoint = 3, chests = {} },
				},
			}
		end

		it("мёртвая сохранка ступени убирается", function()
			local profile = Migrations.normalize(version2Profile(), NOW)

			expect(profile.stages[1].checkpoint).to.equal(nil)
			expect(profile.stages[2].checkpoint).to.equal(nil)
		end)

		it("открытость ступеней при этом не теряется", function()
			local profile = Migrations.normalize(version2Profile(), NOW)

			expect(profile.stages[1].unlocked).to.equal(true)
			expect(profile.stages[2].unlocked).to.equal(true)
			expect(profile.letters.m.mastery).to.equal(2)
		end)

		it("появляется таблица незаконченных забегов", function()
			local profile = Migrations.normalize(version2Profile(), NOW)

			expect(profile.version).to.equal(ProfileTemplate.VERSION)
			expect(typeof(profile.runs)).to.equal("table")
			expect(next(profile.runs)).to.equal(nil)
		end)

		it("уже записанный забег миграция не трогает", function()
			local profile = version2Profile()
			profile.runs = {
				obstacle_course = { challengeId = "obstacle_course", seed = 7, checkpoint = 2 },
			}

			local migrated = Migrations.normalize(profile, NOW)

			expect(migrated.runs.obstacle_course.seed).to.equal(7)
			expect(migrated.runs.obstacle_course.checkpoint).to.equal(2)
		end)

		it(
			"испорченная таблица забегов заменяется пустой",
			function()
				local profile = version2Profile()
				profile.runs = "не таблица"

				local migrated = Migrations.normalize(profile, NOW)

				expect(typeof(migrated.runs)).to.equal("table")
				expect(next(migrated.runs)).to.equal(nil)
			end
		)
	end)

	--[[
		Шаг 3 — у игрока появился участок на спавне. Проверяем, что старый профиль
		получает пустой участок, а не отсутствие поля: ноль — это «дома ещё нет»,
		а nil — это упавший сервис при первой же попытке построить.
	]]
	describe("Миграция 3 → 4: участок игрока", function()
		local function version3Profile()
			return {
				version = 3,
				stars = 500,
				letters = { m = { mastery = 3, correct = 9, wrong = 1, streak = 4, types = {} } },
				stages = { [1] = { unlocked = true, chests = {} } },
				runs = {},
			}
		end

		it("появляется пустой участок", function()
			local profile = Migrations.normalize(version3Profile(), NOW)

			expect(profile.version).to.equal(ProfileTemplate.VERSION)
			expect(typeof(profile.base)).to.equal("table")
			for _, id in Base.ids() do
				expect(profile.base[id]).to.equal(0)
			end
		end)

		it("звёздочки и буквы при этом не трогаются", function()
			local profile = Migrations.normalize(version3Profile(), NOW)

			expect(profile.stars).to.equal(500)
			expect(profile.letters.m.mastery).to.equal(3)
		end)

		it("уже построенный дом миграция не сносит", function()
			local profile = version3Profile()
			profile.base = { house = 2, roof = 1 }

			local migrated = Migrations.normalize(profile, NOW)

			expect(migrated.base.house).to.equal(2)
			expect(migrated.base.roof).to.equal(1)
			expect(migrated.base.yard).to.equal(0)
		end)

		it("испорченный участок не роняет вход в игру", function()
			local profile = version3Profile()
			profile.base = "сарай"

			local migrated = Migrations.normalize(profile, NOW)

			expect(typeof(migrated.base)).to.equal("table")
			expect(migrated.base.house).to.equal(0)
		end)

		it("срез для клиента отдаёт участок", function()
			local profile = ProfileTemplate.new(NOW)
			profile.base.house = 3

			local snapshot = ProfileTemplate.toSnapshot(profile)

			expect(snapshot.base.house).to.equal(3)
			snapshot.base.house = 99
			expect(profile.base.house).to.equal(3)
		end)
	end)

	--[[
		Шаг 4 — открылся мир математики. Проверяем главное: прогресс по буквам
		миграция не трогает вовсе. Две ветки обучения независимы, и появление счёта
		не имеет права стоить ребёнку ни одной выученной буквы.
	]]
	describe("Миграция 4 → 5: прогресс по счёту", function()
		local function version4Profile()
			return {
				version = 4,
				stars = 120,
				letters = { m = { mastery = 2, correct = 5, wrong = 1, streak = 2, types = {} } },
				stages = { [1] = { unlocked = true, chests = {} } },
				runs = {},
				base = { house = 1, roof = 0, yard = 0, fence = 0 },
			}
		end

		it("появляется пустой прогресс по математике", function()
			local profile = Migrations.normalize(version4Profile(), NOW)

			expect(profile.version).to.equal(ProfileTemplate.VERSION)
			expect(typeof(profile.math)).to.equal("table")
			expect(next(profile.math)).to.equal(nil)
		end)

		it("буквы, звёздочки и дом при этом не трогаются", function()
			local profile = Migrations.normalize(version4Profile(), NOW)

			expect(profile.stars).to.equal(120)
			expect(profile.letters.m.mastery).to.equal(2)
			expect(profile.base.house).to.equal(1)
		end)

		it("уже начатый счёт миграция не стирает", function()
			local profile = version4Profile()
			profile.math = { count_group = { mastery = 3, correct = 7, wrong = 0, streak = 5, types = {} } }

			local migrated = Migrations.normalize(profile, NOW)

			expect(migrated.math.count_group.mastery).to.equal(3)
		end)

		it(
			"испорченный прогресс по счёту не роняет вход в игру",
			function()
				local profile = version4Profile()
				profile.math = "семь"

				local migrated = Migrations.normalize(profile, NOW)

				expect(typeof(migrated.math)).to.equal("table")
				expect(next(migrated.math)).to.equal(nil)
			end
		)

		it(
			"срез для клиента отдаёт статусы ступеней счёта",
			function()
				local profile = ProfileTemplate.new(NOW)
				profile.math = { digit_small = { mastery = 2, nextReview = NOW } }

				local snapshot = ProfileTemplate.toSnapshot(profile)

				expect(snapshot.math.digit_small).to.equal(2)
			end
		)
	end)

	describe("Миграция 5 → 6: история занятий", function()
		local function version5Profile()
			return {
				version = 5,
				stars = 40,
				letters = { a = { mastery = 3, correct = 9, wrong = 0, streak = 4, types = {} } },
				math = {},
				dailyStreak = 0,
				stats = { totalPlayMin = 0, sessionsCount = 3, firstJoin = NOW },
			}
		end

		it("история начинается пустой, остальное на месте", function()
			local profile = Migrations.normalize(version5Profile(), NOW)

			expect(profile.version).to.equal(ProfileTemplate.VERSION)
			expect(typeof(profile.playLog)).to.equal("table")
			expect(#profile.playLog).to.equal(0)
			expect(profile.letters.a.mastery).to.equal(3)
			expect(profile.stats.sessionsCount).to.equal(3)
		end)

		it("испорченная история не роняет вход в игру", function()
			local profile = version5Profile()
			profile.playLog = { { day = "вчера", sec = 60 }, { day = 20000, sec = 120 } }

			local migrated = Migrations.normalize(profile, NOW)

			expect(#migrated.playLog).to.equal(1)
			expect(migrated.playLog[1].sec).to.equal(120)
		end)

		it("битую историю чинит и у профиля текущей версии", function()
			local profile = ProfileTemplate.new(NOW)
			profile.playLog = { "мусор", 7, { day = 20000, sec = 300 } }

			local migrated = Migrations.normalize(profile, NOW)

			expect(#migrated.playLog).to.equal(1)
			expect(migrated.playLog[1].sec).to.equal(300)
		end)

		it("история не уходит клиенту в срезе профиля", function()
			local profile = ProfileTemplate.new(NOW)
			profile.playLog = { { day = 20000, sec = 600 } }

			expect(ProfileTemplate.toSnapshot(profile).playLog).to.never.be.ok()
		end)
	end)

	--[[
		Шаг 6 — мир букв стал путём из уровней. Главное: старый туннель без уровня
		выбрасывается (по его рецепту собрался бы другой туннель), а всё прочее,
		что ребёнок заработал, остаётся на месте.
	]]
	describe("Миграция 6 → 7: уровни мира букв", function()
		local function version6Profile()
			return {
				version = 6,
				stars = 75,
				letters = { a = { mastery = 2, correct = 4, wrong = 1, streak = 2, types = {} } },
				runs = {
					tunnel_run = {
						challengeId = "tunnel_run",
						seed = 11,
						letters = { "a", "b" },
						checkpoint = 2,
					},
					math_gates = {
						challengeId = "math_gates",
						seed = 5,
						letters = {},
						stage = 2,
						checkpoint = 1,
					},
				},
			}
		end

		it("путь начинается с первого уровня", function()
			local profile = Migrations.normalize(version6Profile(), NOW)

			expect(profile.version).to.equal(ProfileTemplate.VERSION)
			expect(profile.levels.letters).to.equal(0)
			expect(Levels.current(profile.levels.letters)).to.equal(1)
		end)

		it("туннель старого вида выбрасывается", function()
			local profile = Migrations.normalize(version6Profile(), NOW)

			expect(profile.runs.tunnel_run).to.equal(nil)
		end)

		it("математика, буквы и звёздочки остаются", function()
			local profile = Migrations.normalize(version6Profile(), NOW)

			expect(profile.runs.math_gates.checkpoint).to.equal(1)
			expect(profile.letters.a.mastery).to.equal(2)
			expect(profile.stars).to.equal(75)
		end)

		it("туннель уже с уровнем миграция не трогает", function()
			local profile = version6Profile()
			profile.runs.tunnel_run.level = 3

			local migrated = Migrations.normalize(profile, NOW)

			expect(migrated.runs.tunnel_run.level).to.equal(3)
			expect(migrated.runs.tunnel_run.checkpoint).to.equal(2)
		end)

		it(
			"срез для клиента отдаёт пройденные уровни — для таблички над порталом",
			function()
				local profile = ProfileTemplate.new(NOW)
				profile.levels.letters = 4

				local snapshot = ProfileTemplate.toSnapshot(profile)

				expect(snapshot.levels.letters).to.equal(4)
				snapshot.levels.letters = 11
				expect(profile.levels.letters).to.equal(4)
			end
		)

		it("кто уже играл, обучение получает пройденным", function()
			local profile = Migrations.normalize(version6Profile(), NOW)
			expect(ProfileTemplate.toSnapshot(profile).tutorial).to.equal(nil)
		end)

		it(
			"новичок старой версии проходит обучение с начала",
			function()
				local profile =
					Migrations.normalize({ version = 6, stars = 0, letters = {}, inventory = {} }, NOW)
				expect(ProfileTemplate.toSnapshot(profile).tutorial).to.equal("catch")
			end
		)

		it(
			"у старого профиля появляется напоминание об отдыхе, PIN на месте",
			function()
				local profile = version6Profile()
				profile.parent = { pinHash = "fnv1a-1000:abc", dailyLimitMin = 999 }

				local migrated = Migrations.normalize(profile, NOW)

				expect(migrated.parent.restReminder).to.equal(true)
				expect(migrated.parent.pinHash).to.equal("fnv1a-1000:abc")
				-- 999 минут родитель выставить не мог: это мусор, лимит выключен.
				expect(migrated.parent.dailyLimitMin).to.equal(nil)
			end
		)

		it("новый профиль начинает с Буквопада", function()
			expect(ProfileTemplate.toSnapshot(ProfileTemplate.new(NOW)).tutorial).to.equal("catch")
		end)

		it("испорченный счёт уровней не роняет вход в игру", function()
			for _, broken in
				{ "три", { letters = -4 }, { letters = 999 }, { letters = 2.7 }, { letters = 0 / 0 } }
			do
				local profile = version6Profile()
				profile.levels = broken

				local migrated = Migrations.normalize(profile, NOW)
				local cleared = migrated.levels.letters

				expect(cleared >= 0 and cleared <= Levels.count()).to.equal(true)
				expect(cleared).to.equal(math.floor(cleared))
			end
		end)
	end)
end
