-- Experimental local recommendation engine for Simply Love + ITGmania.
--
-- Target branches for this prototype:
--   ITGmania: beta
--   Simply Love: itgmania-beta
--
-- Requires the accompanying ITGmania HighScoreList Lua binding patch, which
-- exposes HighScoreList:GetNumTimesPlayed() and :GetLastPlayed().

SLRecommendations = SLRecommendations or {}
SLRecommendations.Version = "20"

-- The curriculum is kept in a separate editable file.  Normally Simply Love
-- loads Scripts automatically, but load it explicitly if necessary so this
-- feature does not depend on directory iteration order.
if not SLRecommendationCurriculum then
    local curriculumPath =
        THEME:GetCurrentThemeDirectory() ..
        "Scripts/SL-RecommendationCurriculum.lua"

    if FILEMAN:DoesFileExist(curriculumPath) then
        local loader = loadfile(curriculumPath)
        if loader then loader() end
    end
end

SLRecommendations.Config = {
    Debug = true,

    -- The preferred meter is learned from a weighted median of actually played
    -- charts.  The spread adapts to the player's observed meter distribution.
    DifficultyMinSigma = 1.75,
    DifficultyMaxSigma = 4.00,

    -- Difficulty is not just another additive feature.  It also gates the
    -- final score so wildly inappropriate meters cannot win purely on metadata.
    DifficultyGateFloor = 0.20,

    -- Recency reaches its maximum value after this many days.  These components
    -- only apply to charts that have actually been played; unseen charts use
    -- the exploration component instead.
    PersonalStaleDays = 180,
    MachineStaleDays = 45,

    -- Number of ranked songs exposed when the Simply Love module switches the
    -- wheel into the Recommended preferred sort.
    WheelResultCount = 100,

    -- Recommended-sort UI behavior.
    -- These were accidentally omitted in v8, which meant the module treated
    -- them as false/nil and silently disabled chart selection + helper UI.
    AutoSelectRecommendedSteps = true,
    ShowRecommendationHint = true,

    -- Module integration diagnostics.  Trace logging goes to Logs/Log.txt.
    -- Set RecommendationUIDebugOnScreen=true if you also want SM() popups.
    RecommendationUIDebug = true,
    RecommendationUIDebugOnScreen = false,

    -- Local peer-relative scoring model.
    --
    -- v10 collects this signal and writes it to recommendations-debug.txt,
    -- but does NOT change recommendation ranking yet.  We want to validate
    -- identity dedupe and the learned performance pattern first.
    LocalPeerEnabled = true,

    -- Keep the existing balanced "For You" ranking unchanged for now.
    -- The peer model DOES affect the dedicated "Score Well" section.
    LocalPeerAffectsForYou = false,

    -- Require at least this many OTHER unique people on a chart before using
    -- it as a training example.
    LocalPeerMinOpponents = 2,

    -- Confidence reaches 1.0 once this many unique opponents are available.
    LocalPeerFullConfidenceOpponents = 5,

    -- A score margin of roughly this size is meaningful in the robust
    -- percentile+margin peer score.  0.015 = 1.5 percentage points.
    LocalPeerGapScale = 0.015,

    -- Number/similarity of neighboring peer-rated charts used to predict
    -- performance on an unseen recommendation.
    LocalPeerNeighborCount = 12,
    LocalPeerMinSimilarity = 0.45,
    LocalPeerMeterSigma = 2.0,
    LocalPeerPredictionFullSupport = 3.0,

    -- Fast unseen-chart local-peer predictor.
    LocalPeerRegressionRidge = 2.0,
    LocalPeerRegressionMinExamples = 20,

    -- Cached chart-shape / stamina features.
    --
    -- ITGmania beta already caches RadarValues, Peak NPS, and NPS-per-measure.
    -- This does not parse simfiles.  We reduce the per-measure density data to
    -- a few scalar summaries and cache them once per unique chart identity.
    StaminaDensityEnabled = true,
    DensityHighThreshold = 0.75,

    -- Machine-local scoring-difficulty model.
    --
    -- This is intentionally observation-only in v14.  It learns:
    --
    --     transformed score ~= population baseline
    --                         + player scoring ability
    --                         - chart scoring difficulty
    --
    -- from PASSED scores only.  It then predicts an expected score for the
    -- current player on each candidate.  No recommendation weights use this
    -- value yet.
    LocalScoringDifficultyEnabled = true,

    -- v15 promotes only the ROBUST RELATIVE EASE signal into Score Well.
    -- The literal expected PercentDP remains diagnostic because v14 showed
    -- that exact-score prediction is too noisy to use directly.
    LocalScoringDifficultyAffectsRanking = true,
    LocalScoringDifficultyIterations = 8,
    LocalScoringDifficultyPlayerRidge = 4.0,
    LocalScoringDifficultyChartRidge = 4.0,
    LocalScoringDifficultyMinPlayersPerChart = 3,
    LocalScoringDifficultyMinChartsPerPlayer = 3,
    LocalScoringDifficultyRegressionRidge = 3.0,

    -- Cold-start / progression defaults.  Most curriculum policy lives in
    -- SL-RecommendationCurriculum.lua so it can be edited without changing
    -- the recommender implementation.
    ColdStartDefaultMeter = 6,
    ColdStartDifficultySigma = 3.0,
    PersonalConfidenceFullPassedCharts = 25,
    ScoreWellMinBenchmarkCharts = 8,
    MachineRecentActivityDays = 120,
    CommunityScoreFloor = 0.75,
    LevelUpSigma = 0.80,

    -- Favorites are song-level metadata evidence.  Do not let a favorite imply
    -- that every chart for that song is liked.  We only boost chart-specific
    -- learning for charts the player actually played.
    FavoritePlayedChartBoost = 1.25,
    FavoriteSongMetadataBoost = 1.00,

    -- Component weights sum to 1.0.  Missing/unavailable evidence contributes
    -- zero rather than causing the remaining components to be renormalized up.
    Weights = {
        difficulty = 0.25,
        tech = 0.17,
        metadata = 0.12,
        personalAffinity = 0.08,
        personalFreshness = 0.07,
        machineFreshness = 0.03,
        popularity = 0.05,
        priorPositive = 0.08,
        exploration = 0.15,
    },
}


-- Multiple recommendation intents share the SAME expensive player/chart model.
-- Only the cheap final weighting/ranking changes between sections.
SLRecommendations.Modes = {
    ForYou = {
        section = "For You",
        weights = SLRecommendations.Config.Weights,
        difficultyGateFloor = SLRecommendations.Config.DifficultyGateFloor,
    },

    YouMightLike = {
        section = "You Might Like",
        difficultyGateFloor = 0.30,
        weights = {
            difficulty = 0.15,
            tech = 0.17,
            stamina = 0.17,
            metadata = 0.33,
            personalAffinity = 0.04,
            personalFreshness = 0.00,
            machineFreshness = 0.00,
            popularity = 0.02,
            priorPositive = 0.00,
            exploration = 0.12,
            localPeerPerformance = 0.00,
        },
    },

    ScoreWell = {
        section = "Score Well",
        difficultyGateFloor = 0.20,
        weights = {
            difficulty = 0.20,
            tech = 0.13,
            stamina = 0.13,
            metadata = 0.01,
            personalAffinity = 0.02,
            personalFreshness = 0.00,
            machineFreshness = 0.00,
            popularity = 0.00,
            priorPositive = 0.08,
            exploration = 0.00,
            localPeerPerformance = 0.30,
            localScoringEase = 0.13,
        },
    },

    PopularPicks = {
        section = "Popular Picks",
        difficultyGateFloor = 0.35,
        weights = {
            difficulty = 0.25,
            popularity = 0.27,
            machineRecentActivity = 0.17,
            communityFavorite = 0.16,
            communityScoreability = 0.08,
            beginnerSafety = 0.07,
        },
    },

    LevelUp = {
        section = "Level Up",
        difficultyGateFloor = 0.45,
        weights = {},
    },
}

-- This is only the fallback/static order.  v16 builds the actual order from
-- profile maturity plus the editable curriculum schema.
SLRecommendations.ModeOrder = {
    "ForYou",
    "LevelUp",
    "ScoreWell",
    "YouMightLike",
    "PopularPicks",
}

local TECH_CATEGORIES = {
    "TechCountsCategory_Crossovers",
    "TechCountsCategory_HalfCrossovers",
    "TechCountsCategory_FullCrossovers",
    "TechCountsCategory_Footswitches",
    "TechCountsCategory_UpFootswitches",
    "TechCountsCategory_DownFootswitches",
    "TechCountsCategory_Sideswitches",
    "TechCountsCategory_Jacks",
    "TechCountsCategory_Brackets",
    "TechCountsCategory_Doublesteps",
}


local DEFAULT_CURRICULUM = {
    JokeMeterMax = 30,
    Skill = {
        decentDP = 0.80,
        strongDP = 0.90,
        reliableMinCharts = 2,
        masteryMinCharts = 4,
        strongMasteryMinCharts = 3,
    },
    RecentInterest = {
        minLevel = 9,
        lookbackDays = 120,
        minCharts = 2,
        minNormalizedInterest = 0.35,
        maxSections = 2,
    },
    NotationStrength = {
        minus = 0.45,
        plain = 0.72,
        plus = 0.90,
        doublePlus = 1.00,
    },
    Quirkiness = {
        automaticLevel = 10,
        section = "Quirky Recs",
        interestSection = "More Quirky Charts",
        candidateMin = 0.42,
        maxResults = 20,
        interestMaxResults = 16,
        interestMinLevel = 10,
        interestLookbackDays = 120,
        interestMinCharts = 2,
        interestMin = 0.32,
        editDifficultyPoints = 0.10,
    },
    Rhythms = {
        section = "More Rhythms",
        notation = {"RH", "SKT", "RHYTHM", "RHYTHMS", "SKITTLE", "SKITTLES"},
        streamNotation = {"STR", "STREAM", "STREAMS"},
        chaosThreshold = 1.20,
        chaosFull = 2.25,
        beginnerChaosThreshold = 1.00,
        beginnerChaosFull = 2.00,
        candidateMin = 0.42,
        interestLookbackDays = 120,
        interestMinCharts = 2,
        interestMin = 0.34,
        interestMinLevel = 9,
        earlyInterestFamiliarity = 0.65,
        maxResults = 16,
        familiarityPassedCharts = 3,
        familiarityRecentCharts = 4,
        goodScoreDP = 0.80,
        frequentPlayCount = 3,
        beginnerPenaltyStrength = 0.88,
    },
    Tech = {},
    Levels = {},
    Bands = {},
}

local function curriculum()
    return SLRecommendationCurriculum or DEFAULT_CURRICULUM
end

local TECH_FEATURE_INDEX = {
    crossovers = 1,
    footswitches = 4,
    sideswitches = 7,
    jacks = 8,
    brackets = 9,
    doublesteps = 10,
}

local INVALID_METADATA = {
    [""] = true,
    ["-"] = true,
    ["unknown"] = true,
    ["unknown artist"] = true,
    ["none"] = true,
    ["n/a"] = true,
    ["na"] = true,
    ["null"] = true,
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function trim(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function normalizeMetadata(s)
    s = trim(s):lower()
    s = s:gsub("%s+", " ")
    if INVALID_METADATA[s] then return nil end
    return s
end

-- A lot of community files append pattern/count shorthand to #CREDIT, such as:
--   "JWong 124*|86*"
--   "YUZU 66-187*/49"
-- Preserve ordinary multi-word names (e.g. "Crash Cringle") while stripping a
-- trailing token made only of numeric/stat punctuation.
local function normalizeCredit(s)
    s = trim(s)
    if s == "" then return nil end

    local base = s:match("^(.-)%s+[%d%*%|/%-%.]+$")
    if base and trim(base) ~= "" then
        s = trim(base)
    end

    return normalizeMetadata(s)
end

local function profileIsGuest(profile)
    return profile
        and profile.GetType
        and tostring(profile:GetType()) == "ProfileType_Guest"
end

local function songCommunityKey(song)
    if not song or not song.GetSongDir then return nil end

    local dir = tostring(song:GetSongDir() or "")
    local parts = {}
    for part in dir:gmatch("[^/]+") do
        parts[#parts + 1] = part
    end

    if #parts < 2 then return nil end
    return (parts[#parts - 1] .. "/" .. parts[#parts]):lower()
end

local function buildCommunityFavorites()
    local counts = {}
    local maxCount = 0
    local contributingProfiles = 0

    for profileID in ivalues(PROFILEMAN:GetLocalProfileIDs() or {}) do
        local profile = PROFILEMAN:GetLocalProfile(profileID)

        if profile and not profileIsGuest(profile) then
            local path = PROFILEMAN:LocalProfileIDToDir(profileID) .. "favorites.txt"
            if FILEMAN:DoesFileExist(path) and lua and lua.ReadFile then
                local contents = lua.ReadFile(path)
                if type(contents) == "string" and contents ~= "" then
                    local seen = {}
                    local contributed = false
                    for line in contents:gmatch("[^\\r\\n]+") do
                        line = trim(line)
                        if line ~= "" and not line:find("^%-%-%-") then
                            local key = line:lower()
                            if not seen[key] then
                                seen[key] = true
                                counts[key] = (counts[key] or 0) + 1
                                maxCount = math.max(maxCount, counts[key])
                                contributed = true
                            end
                        end
                    end
                    if contributed then
                        contributingProfiles = contributingProfiles + 1
                    end
                end
            end
        end
    end

    return counts, maxCount, contributingProfiles
end

local function log1p(x)
    if not x or x <= 0 then return 0 end
    return math.log(1 + x)
end

local function median(values)
    if not values or #values == 0 then return nil end

    local copy = {}
    for i, value in ipairs(values) do
        copy[i] = value
    end
    table.sort(copy)

    local n = #copy
    if n % 2 == 1 then
        return copy[(n + 1) / 2]
    end

    return (copy[n / 2] + copy[n / 2 + 1]) / 2
end

local function gaussian(distance, sigma)
    sigma = math.max(0.001, sigma or 1)
    return math.exp(-0.5 * (distance / sigma) * (distance / sigma))
end

local function profileSlotForPlayer(pn)
    return ProfileSlot[PlayerNumber:Reverse()[pn] + 1]
end

local function getPlayerProfile(pn)
    if not PROFILEMAN:IsPersistentProfile(pn) then return nil end
    return PROFILEMAN:GetProfile(pn)
end


local function getHSL(profile, song, steps)
    if not profile or not song or not steps then return nil end
    return profile:GetHighScoreListIfExists(song, steps)
end

local function getPlayCount(profile, song, steps)
    local hsl = getHSL(profile, song, steps)
    if not hsl or not hsl.GetNumTimesPlayed then return 0 end
    return hsl:GetNumTimesPlayed() or 0
end

local function getBestPercentDP(profile, song, steps)
    local hsl = getHSL(profile, song, steps)
    if not hsl then return nil end

    local best = nil
    for score in ivalues(hsl:GetHighScores() or {}) do
        local dp = score:GetPercentDP()
        if dp and (not best or dp > best) then
            best = dp
        end
    end
    return best
end


local function isPassedHighScore(highScore)
    if not highScore then return false end

    local grade = highScore:GetGrade()
    return grade ~= "Grade_Failed"
        and grade ~= "Grade_NoData"
end

local function getBestPassedPercentDP(profile, song, steps)
    local hsl = getHSL(profile, song, steps)
    if not hsl then return nil, 0 end

    local best = nil
    local excluded = 0

    for highScore in ivalues(hsl:GetHighScores() or {}) do
        if isPassedHighScore(highScore) then
            local dp = highScore:GetPercentDP()
            if dp and (not best or dp > best) then
                best = dp
            end
        else
            excluded = excluded + 1
        end
    end

    return best, excluded
end

-- ITGmania's theme Lua runtime exposes calendar globals such as Year(),
-- MonthOfYear(), and DayOfMonth(), but intentionally does not load Lua's
-- standard `os` library.  Convert Gregorian dates to an integer day number
-- directly so freshness can remain entirely theme-side.
local function civilDateToDayNumber(year, month, day)
    -- Howard Hinnant's "days from civil" algorithm, adapted for Lua.
    -- The absolute epoch is irrelevant because we only subtract two results.
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)

    if not year or not month or not day then return nil end

    if month <= 2 then
        year = year - 1
    end

    local era
    if year >= 0 then
        era = math.floor(year / 400)
    else
        era = math.floor((year - 399) / 400)
    end

    local yoe = year - era * 400
    local mp = month + (month > 2 and -3 or 9)
    local doy = math.floor((153 * mp + 2) / 5) + day - 1
    local doe =
        yoe * 365 +
        math.floor(yoe / 4) -
        math.floor(yoe / 100) +
        doy

    return era * 146097 + doe
end

local function parseDateParts(s)
    if type(s) ~= "string" then return nil end

    -- Accept both:
    --   YYYY-MM-DD
    --   YYYY-MM-DD HH:MM:SS
    local y, mo, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if not y then return nil end

    return tonumber(y), tonumber(mo), tonumber(d)
end

local function getDaysSinceLastPlayed(profile, song, steps)
    local hsl = getHSL(profile, song, steps)
    if not hsl or getPlayCount(profile, song, steps) <= 0 then
        return nil
    end

    local lastPlayed = hsl:GetLastPlayed()
    local y, mo, d = parseDateParts(lastPlayed)
    if not y then return nil end

    local lastDay = civilDateToDayNumber(y, mo, d)
    local today = civilDateToDayNumber(
        Year(),
        MonthOfYear() + 1,
        DayOfMonth()
    )

    if not lastDay or not today then return nil end

    return math.max(0, today - lastDay)
end

local function isFavorited(pn, song)
    if not SL or not song then return false end
    local key = ToEnumShortString(pn)
    if not SL[key] or type(SL[key].Favorites) ~= "table" then return false end

    for favorite in ivalues(SL[key].Favorites) do
        if favorite == song then return true end
    end
    return false
end


local function getGrooveStatsIdentity(steps)
    if not steps or not steps.GetGrooveStatsHash then return nil, nil end

    local hash = trim(steps:GetGrooveStatsHash() or "")
    if hash == "" then return nil, nil end

    local version = nil
    if steps.GetGrooveStatsHashVersion then
        version = steps:GetGrooveStatsHashVersion()
    end

    return hash, version
end

-- Prefer the installed copy that has the strongest actual history.  This is
-- intentionally max-based, not additive: duplicate installs of the same GS
-- chart must not make that chart look more popular merely because it exists in
-- several packs.
local function isBetterRepresentative(a, b)
    if not b then return true end

    if a.playerPlays ~= b.playerPlays then
        return a.playerPlays > b.playerPlays
    end

    if a.machinePlays ~= b.machinePlays then
        return a.machinePlays > b.machinePlays
    end

    if a.favorite ~= b.favorite then
        return a.favorite
    end

    local at = (a.song:GetDisplayFullTitle() or ""):lower()
    local bt = (b.song:GetDisplayFullTitle() or ""):lower()
    if at ~= bt then return at < bt end

    return (a.steps:GetMeter() or 0) < (b.steps:GetMeter() or 0)
end

local function chooseRepresentative(entries, requireDisplayed)
    local best = nil
    for _, entry in ipairs(entries) do
        if not requireDisplayed or entry.song:NormallyDisplayed() then
            if isBetterRepresentative(entry, best) then
                best = entry
            end
        end
    end
    return best
end

local function collectChartGroups(pn, stepsType, personalProfile)
    local machine = PROFILEMAN:GetMachineProfile()
    local groupsByKey = {}
    local groups = {}
    local fallbackIdentity = 0
    local totalEntries = 0

    for song in ivalues(SONGMAN:GetAllSongs()) do
        local favorite = personalProfile and isFavorited(pn, song) or false

        for steps in ivalues(song:GetStepsByStepsType(stepsType) or {}) do
            totalEntries = totalEntries + 1

            local hash, hashVersion = getGrooveStatsIdentity(steps)
            local key
            if hash then
                -- The hash itself is the identity.  Keep the version as debug
                -- metadata but do not let two copies of the same returned hash
                -- survive merely because their stored version metadata differs.
                key = "gs:" .. hash
            else
                -- No hash means no cross-install dedupe.  Make this runtime
                -- entry unique rather than guessing from title/path metadata.
                fallbackIdentity = fallbackIdentity + 1
                key = "local:" .. tostring(fallbackIdentity)
            end

            local group = groupsByKey[key]
            if not group then
                group = {
                    key = key,
                    grooveStatsHash = hash,
                    grooveStatsHashVersion = hashVersion,
                    entries = {},
                    favorite = false,
                }
                groupsByKey[key] = group
                groups[#groups + 1] = group
            end

            local entry = {
                song = song,
                steps = steps,
                favorite = favorite,
                playerPlays = getPlayCount(personalProfile, song, steps),
                machinePlays = getPlayCount(machine, song, steps),
                grooveStatsHash = hash,
                grooveStatsHashVersion = hashVersion,
            }

            group.entries[#group.entries + 1] = entry
            group.favorite = group.favorite or favorite
        end
    end

    local duplicateHashGroups = 0
    local duplicateChartCopiesCollapsed = 0

    for _, group in ipairs(groups) do
        group.representative = chooseRepresentative(group.entries, false)
        group.copyCount = #group.entries

        if group.grooveStatsHash and group.copyCount > 1 then
            duplicateHashGroups = duplicateHashGroups + 1
            duplicateChartCopiesCollapsed =
                duplicateChartCopiesCollapsed + (group.copyCount - 1)
        end
    end

    return groups, {
        totalEntries = totalEntries,
        uniqueIdentities = #groups,
        duplicateHashGroups = duplicateHashGroups,
        duplicateChartCopiesCollapsed = duplicateChartCopiesCollapsed,
    }
end

local function getTechVector(steps, pn, song)
    local result = {}
    local raw = {}
    local tc = steps:GetTechCounts(pn)
    local seconds = math.max(1, song:GetStepsSeconds())
    local minutes = seconds / 60

    for i, category in ipairs(TECH_CATEGORIES) do
        local value = tc:GetValue(category) or 0
        -- Unknown tech counts are represented as -1.
        if value < 0 then value = 0 end
        raw[i] = value
        result[i] = value / minutes
    end

    return result, raw
end

local function vectorMagnitude(v)
    local sum = 0
    for i = 1, #v do
        sum = sum + v[i] * v[i]
    end
    return math.sqrt(sum)
end

local function cosineSimilarity(a, b)
    if not a or not b or #a == 0 or #a ~= #b then return nil end

    local dot = 0
    for i = 1, #a do
        dot = dot + a[i] * b[i]
    end

    local denom = vectorMagnitude(a) * vectorMagnitude(b)
    if denom <= 0 then return nil end
    return clamp(dot / denom, 0, 1)
end

-- Cosine similarity captures the shape of the tech profile but ignores overall
-- intensity.  Blend in a magnitude comparison so a very light chart does not
-- look identical to a very dense chart with the same proportions.
local function techFeatureRate(tech, feature)
    local index = TECH_FEATURE_INDEX[feature]
    if not index then return 0 end
    return math.max(0, tonumber(tech and tech[index]) or 0)
end

local function techFeatureRawCount(raw, feature)
    local index = TECH_FEATURE_INDEX[feature]
    if not index then return 0 end
    return math.max(0, tonumber(raw and raw[index]) or 0)
end

local function parseChartNotation(steps)
    local description = ""
    local chartStyle = ""

    if steps and steps.GetDescription then
        description = tostring(steps:GetDescription() or "")
    end
    if steps and steps.GetChartStyle then
        chartStyle = tostring(steps:GetChartStyle() or "")
    end

    local source = trim(description .. " " .. chartStyle)
    local upper = source:upper()
    local tokens = {}
    local display = {}

    for token in upper:gmatch("[A-Z0-9]+[%+%-]*") do
        local base, modifier = token:match("^([A-Z0-9]+)([%+%-]*)$")
        if base then
            local strengthCfg = curriculum().NotationStrength or {}
            local strength
            if modifier:find("%+%+") then
                strength = tonumber(strengthCfg.doublePlus) or 1.00
            elseif modifier:find("%+") then
                strength = tonumber(strengthCfg.plus) or 0.90
            elseif modifier:find("%-") then
                strength = tonumber(strengthCfg.minus) or 0.45
            else
                strength = tonumber(strengthCfg.plain) or 0.72
            end

            if not tokens[base] or strength > tokens[base] then
                tokens[base] = strength
            end
            display[#display + 1] = token
        end
    end

    return {
        source = source,
        tokens = tokens,
        display = display,
    }
end

local function notationStrengthForAliases(notation, aliases)
    if not notation then return 0, nil end

    local best = 0
    local bestToken = nil

    for _, alias in ipairs(aliases or {}) do
        local token = tostring(alias):upper()
        local strength = notation.tokens[token] or 0

        if strength > best then
            best = strength
            bestToken = token
        end
    end

    return best, bestToken
end

local function notationIntensityFromStrength(strength)
    if not strength or strength <= 0 then return 0 end

    local intensityCfg =
        curriculum().NotationIntensity or {}

    local strengthCfg =
        curriculum().NotationStrength or {}

    local minus =
        tonumber(strengthCfg.minus) or 0.45

    local plain =
        tonumber(strengthCfg.plain) or 0.72

    local plus =
        tonumber(strengthCfg.plus) or 0.90

    if strength <= minus + 0.0001 then
        return tonumber(intensityCfg.minus) or 0.25
    elseif strength <= plain + 0.0001 then
        return tonumber(intensityCfg.plain) or 0.50
    elseif strength <= plus + 0.0001 then
        return tonumber(intensityCfg.plus) or 0.80
    end

    return tonumber(intensityCfg.doublePlus) or 1.00
end

local function notationStrengthForFeature(notation, feature)
    local spec = curriculum().Tech and curriculum().Tech[feature]
    if not spec then return 0, nil end

    return notationStrengthForAliases(
        notation,
        spec.notation
    )
end

local function techFeatureEvidence(tech, raw, notation, feature)
    local spec = curriculum().Tech and curriculum().Tech[feature]
    if not spec then
        return {
            fit = 0,
            intensity = 0,

            engineFit = 0,
            engineIntensity = 0,
            engineCount = 0,
            engineRate = 0,
            countIntensity = 0,
            rateIntensity = 0,

            notationStrength = 0,
            notationIntensity = 0,
            notationToken = nil,

            masteryEligible = false,
        }
    end

    local rate = techFeatureRate(tech, feature)
    local count = techFeatureRawCount(raw, feature)
    local minCount = math.max(1, tonumber(spec.minEngineCount) or 3)
    local fullRate = math.max(0.05, tonumber(spec.fullFitRate) or 0.5)
    local notationStrength, notationToken =
        notationStrengthForFeature(notation, feature)

    -- Presence / eligibility evidence.
    --
    -- This intentionally answers "is this legitimately a chart with this
    -- technique?" and remains separate from the intensity used for ranking.
    local engineFit = 0
    if count >= minCount then
        engineFit = clamp(1 - math.exp(-rate / fullRate), 0, 1)
    end

    local fit = math.max(engineFit, notationStrength)

    -- Dedicated-tech ranking needs a signal that DOES NOT saturate after just
    -- a few pattern events.  Balance total count with count-per-minute so long
    -- charts do not automatically win while short dense charts remain strong.
    local heavyCount =
        math.max(
            minCount,
            tonumber(spec.heavyEngineCount)
                or (minCount * 5)
        )

    local heavyRate =
        math.max(
            0.05,
            tonumber(spec.heavyEngineRate)
                or (fullRate * 8)
        )

    local countIntensity =
        clamp(count / heavyCount, 0, 1)

    local rateIntensity =
        clamp(rate / heavyRate, 0, 1)

    local engineIntensity = 0
    if count >= minCount then
        engineIntensity =
            0.65 * countIntensity +
            0.35 * rateIntensity
    end

    -- Notation has a separate intensity interpretation.
    --
    -- Plain "BR"/"FS"/etc. = definite presence, not maximum intensity.
    -- "-" is light, "+" is heavy, and "++" is very heavy.
    local notationIntensity =
        notationIntensityFromStrength(
            notationStrength
        )

    local intensity =
        math.max(
            engineIntensity,
            notationIntensity
        )

    -- Low-density '-' notation is valid recommendation evidence, but does not
    -- by itself count as a full mastery-training chart.
    local masteryNotationMin =
        tonumber(spec.masteryNotationMin) or
        tonumber((curriculum().NotationStrength or {}).plain) or 0.72

    return {
        fit = fit,
        intensity = intensity,

        engineFit = engineFit,
        engineIntensity = engineIntensity,
        engineCount = count,
        engineRate = rate,
        countIntensity = countIntensity,
        rateIntensity = rateIntensity,

        notationStrength = notationStrength,
        notationIntensity = notationIntensity,
        notationToken = notationToken,

        masteryEligible =
            count >= minCount
            or notationStrength >= masteryNotationMin,
    }
end

local function techFeatureFit(tech, feature, raw, notation)
    return techFeatureEvidence(tech, raw, notation, feature).fit
end

local function getRhythmEvidence(shape, notation)
    local cfg = curriculum().Rhythms or {}

    local notationStrength, notationToken =
        notationStrengthForAliases(
            notation,
            cfg.notation or {}
        )

    local notationIntensity =
        notationIntensityFromStrength(
            notationStrength
        )

    local streamNotationStrength =
        select(
            1,
            notationStrengthForAliases(
                notation,
                cfg.streamNotation or {}
            )
        )

    local chaos =
        tonumber(
            shape
            and shape.radarChaos
            or 0
        ) or 0

    local threshold =
        tonumber(cfg.chaosThreshold)
        or 1.20

    local full =
        math.max(
            threshold + 0.01,
            tonumber(cfg.chaosFull)
                or 2.25
        )

    local chaosPresence = 0

    if chaos >= threshold then
        chaosPresence =
            0.45 +
            0.55 *
            clamp(
                (chaos - threshold) /
                (full - threshold),
                0,
                1
            )
    end

    local chaosRecommendation =
        chaosPresence

    -- ITGmania Chaos counts 12th-or-finer rows, so straight 16th stream can
    -- also produce high values.  If the charter explicitly labels STR/STREAM
    -- but not RH/SKT/Rhythms, reduce the Chaos-only Rhythm interpretation.
    if notationStrength <= 0
        and streamNotationStrength > 0
    then
        chaosRecommendation =
            chaosRecommendation * 0.65
    end

    local evidence =
        math.max(
            notationStrength,
            chaosRecommendation
        )

    local intensity =
        math.max(
            notationIntensity,
            chaosRecommendation
        )

    local beginnerThreshold =
        tonumber(cfg.beginnerChaosThreshold)
        or 1.00

    local beginnerFull =
        math.max(
            beginnerThreshold + 0.01,
            tonumber(cfg.beginnerChaosFull)
                or 2.00
        )

    local chaosComplexity = 0

    if chaos >= beginnerThreshold then
        chaosComplexity =
            0.35 +
            0.65 *
            clamp(
                (chaos - beginnerThreshold) /
                (beginnerFull - beginnerThreshold),
                0,
                1
            )
    end

    local complexity =
        math.max(
            notationStrength,
            chaosComplexity
        )

    return {
        evidence = clamp(evidence, 0, 1),
        intensity = clamp(intensity, 0, 1),
        complexity = clamp(complexity, 0, 1),

        notationStrength = notationStrength,
        notationIntensity = notationIntensity,
        notationToken = notationToken,

        streamNotationStrength =
            streamNotationStrength,

        chaos = chaos,
        chaosPresence = chaosPresence,
        chaosRecommendation =
            chaosRecommendation,
        chaosComplexity =
            chaosComplexity,
    }
end

local function rhythmBeginnerSafety(
    model,
    rhythm,
    playerPlays,
    passedDP
)
    local level =
        model.skillFocusLevel
        or model.skillComfortMeter
        or SLRecommendations.Config.ColdStartDefaultMeter
        or 6

    if level >= 9 then return 1 end

    rhythm = rhythm or {
        complexity = 0,
    }

    if (rhythm.complexity or 0) <= 0 then
        return 1
    end

    local cfg =
        curriculum().Rhythms or {}

    local familiarity =
        clamp(
            model.rhythmFamiliarity
            or 0,
            0,
            1
        )

    local directPlayFamiliarity =
        clamp(
            (playerPlays or 0) /
            math.max(
                1,
                tonumber(cfg.frequentPlayCount)
                    or 3
            ),
            0,
            1
        )

    local goodDP =
        tonumber(cfg.goodScoreDP)
        or 0.80

    local directScoreFamiliarity = 0

    if passedDP then
        directScoreFamiliarity =
            clamp(
                (passedDP - (goodDP - 0.10)) /
                0.20,
                0,
                1
            )
    end

    familiarity =
        math.max(
            familiarity,
            directPlayFamiliarity,
            directScoreFamiliarity
        )

    local penaltyStrength =
        clamp(
            tonumber(cfg.beginnerPenaltyStrength)
                or 0.88,
            0,
            1
        )

    return clamp(
        1 -
        (rhythm.complexity or 0) *
        penaltyStrength *
        (1 - familiarity),
        0.08,
        1
    )
end

local function safeTableCount(value)
    return type(value) == "table" and #value or 0
end

local function getRadarCount(radar, category)
    if not radar then return 0 end
    local value = radar:GetValue(category)
    return math.max(0, tonumber(value) or 0)
end

local function getChartQuirkiness(model, steps, song, group, notation)
    model.chartQuirkCache = model.chartQuirkCache or {}

    local key = group and group.key
        or (tostring(song:GetSongDir()) .. "|" .. tostring(steps))
    local cached = model.chartQuirkCache[key]
    if cached then return cached end

    notation = notation or parseChartNotation(steps)
    local timing = steps:GetTimingData()
    local radar = steps:GetRadarValues(model.pn)
    local points = 0
    local reasons = {}

    local function add(value, reason)
        if value and value > 0 then
            points = points + value
            reasons[#reasons + 1] = reason .. "+" .. string.format("%.2f", value)
        end
    end

    local modsStrength = notation.tokens.MODS or 0
    local xmodStrength = notation.tokens.XMOD or 0
    local hasMods = modsStrength > 0
    local hasXmod = xmodStrength > 0
    if hasMods then add(1.50 + 0.75 * modsStrength, "MODS notation") end
    if hasXmod then add(1.00 + 0.75 * xmodStrength, "XMOD notation") end

    local fgCount = 0
    if song.GetFGChanges then
        fgCount = safeTableCount(song:GetFGChanges())
        if fgCount > 0 then
            add(2.00 + math.min(1.00, (fgCount - 1) * 0.25), "FGChanges")
        end
    end

    local bgCount = 0
    if song.GetBGChanges then
        bgCount = safeTableCount(song:GetBGChanges())
        if bgCount > 0 then
            add(math.min(0.55, 0.05 + math.max(0, bgCount - 1) * 0.08), "BGChanges")
        end
    end

    local isEdit =
        tostring(
            steps:GetDifficulty()
            or ""
        ) == "Difficulty_Edit"

    if isEdit then
        add(
            tonumber(
                (curriculum().Quirkiness or {}).editDifficultyPoints
            ) or 0.10,
            "Difficulty_Edit"
        )
    end

    local bpmCount = 0
    if timing.HasBPMChanges and timing:HasBPMChanges() then
        bpmCount = timing.GetBPMs and safeTableCount(timing:GetBPMs()) or 2
        add(math.min(1.00, 0.25 + math.max(0, bpmCount - 2) * 0.12), "BPM changes")
    end

    local speedCount = 0
    if timing.HasSpeedChanges and timing:HasSpeedChanges() then
        speedCount = timing.GetSpeeds and safeTableCount(timing:GetSpeeds()) or 1
        add(math.min(1.75, 0.90 + math.max(0, speedCount - 1) * 0.15), "speed changes")
    end

    local scrollCount = 0
    if timing.HasScrollChanges and timing:HasScrollChanges() then
        scrollCount = timing.GetScrolls and safeTableCount(timing:GetScrolls()) or 1
        add(math.min(1.75, 0.90 + math.max(0, scrollCount - 1) * 0.15), "scroll changes")
    end

    local stopCount = 0
    if timing.HasStops and timing:HasStops() then
        stopCount = timing.GetStops and safeTableCount(timing:GetStops()) or 1
        add(math.min(0.80, 0.20 + stopCount * 0.08), "stops")
    end

    local delayCount = 0
    if timing.HasDelays and timing:HasDelays() then
        delayCount = timing.GetDelays and safeTableCount(timing:GetDelays()) or 1
        add(math.min(0.90, 0.25 + delayCount * 0.08), "delays")
    end

    local warpCount = 0
    if timing.HasWarps and timing:HasWarps() then
        warpCount = timing.GetWarps and safeTableCount(timing:GetWarps()) or 1
        add(math.min(1.25, 0.50 + warpCount * 0.12), "warps")
    end

    local timingFakeCount = 0
    if timing.HasFakes and timing:HasFakes() then
        timingFakeCount = timing.GetFakes and safeTableCount(timing:GetFakes()) or 1
    end
    local significantTiming = steps.HasSignificantTimingChanges
        and steps:HasSignificantTimingChanges() or false
    if significantTiming then add(0.45, "CMod-unsafe timing") end

    if steps.HasAttacks and steps:HasAttacks() then
        add(1.50, "attacks/mods")
    end

    local taps = getRadarCount(radar, "RadarCategory_TapsAndHolds")
    local mines = getRadarCount(radar, "RadarCategory_Mines")
    local hands = getRadarCount(radar, "RadarCategory_Hands")
    local lifts = getRadarCount(radar, "RadarCategory_Lifts")
    local radarFakes = getRadarCount(radar, "RadarCategory_Fakes")

    if mines > 0 then
        local ratio = mines / math.max(1, taps)
        add(0.10 + math.min(0.85, ratio * 1.20), "mines")
        if mines > taps then add(1.20, "more mines than steps") end
    end

    if lifts > 0 then
        add(0.55 + math.min(1.60, lifts / 8 * 0.55), "lifts")
    end

    local fakeCount = math.max(radarFakes, timingFakeCount)
    if fakeCount > 0 then
        add(0.60 + math.min(1.40, fakeCount / 12 * 0.70), "fakes")
    end

    if hands > 0 then
        add(math.min(0.30, 0.05 + hands / 20 * 0.10), "hands")
    end

    local jokeMax = curriculum().JokeMeterMax or 30
    if steps:GetMeter() > jokeMax then
        add(1.50, "joke meter")
    end

    local score = clamp(1 - math.exp(-points / 3.0), 0, 1)
    local result = {
        score = score,
        points = points,
        reasons = reasons,
        fgCount = fgCount,
        bgCount = bgCount,
        isEdit = isEdit,
        bpmCount = bpmCount,
        speedCount = speedCount,
        scrollCount = scrollCount,
        stopCount = stopCount,
        delayCount = delayCount,
        warpCount = warpCount,
        fakeCount = fakeCount,
        mines = mines,
        taps = taps,
        lifts = lifts,
        hands = hands,
        significantTiming = significantTiming,
        hasModsNotation = hasMods,
        hasXmodNotation = hasXmod,
    }

    model.chartQuirkCache[key] = result
    return result
end

local ADVANCED_BEGINNER_FEATURES = {
    "footswitches",
    "sideswitches",
    "brackets",
    "doublesteps",
}

local function beginnerSafetyForTech(model, tech, allowedFeature)
    local level = model.skillFocusLevel or model.skillComfortMeter or 0
    if model.playerMaturity == "established" or level > 10 then
        return 1
    end

    local burden = 0
    for _, feature in ipairs(ADVANCED_BEGINNER_FEATURES) do
        if feature ~= allowedFeature then
            local candidateRate = techFeatureRate(tech, feature)
            local mastery = model.techMastery and model.techMastery[feature]
            local familiar = mastery and mastery.familiarity or 0
            burden = burden + candidateRate * (1 - 0.85 * familiar)
        end
    end

    return math.exp(-burden / 1.25)
end

local function getMachineScoreability(machine, entry)
    if not machine or not entry then return 0 end
    local hsl = getHSL(machine, entry.song, entry.steps)
    if not hsl then return 0 end

    local scores = {}
    for hs in ivalues(hsl:GetHighScores() or {}) do
        if isPassedHighScore(hs) then
            local dp = hs:GetPercentDP()
            if dp then scores[#scores + 1] = dp end
        end
    end

    local med = median(scores)
    if not med then return 0 end

    local floor = SLRecommendations.Config.CommunityScoreFloor
    return clamp((med - floor) / math.max(0.01, 1 - floor), 0, 1)
end

local function techSimilarity(a, b)
    local cosine = cosineSimilarity(a, b)
    if cosine == nil then return nil end

    local ma = vectorMagnitude(a)
    local mb = vectorMagnitude(b)
    if ma <= 0 or mb <= 0 then return cosine end

    local magnitudeSimilarity = math.exp(-math.abs(math.log(1 + ma) - math.log(1 + mb)))
    return clamp(0.70 * cosine + 0.30 * magnitudeSimilarity, 0, 1)
end



local STAMINA_FEATURE_SPECS = {
    -- Feature,             weight, similarity scale
    {"logDuration",          0.14,   0.50},
    {"logPeakNps",           0.15,   0.30},
    {"radarStream",          0.13,   0.35},
    {"radarVoltage",         0.10,   0.45},
    {"radarAir",             0.05,   0.35},
    {"radarFreeze",          0.04,   0.35},
    {"radarChaos",           0.05,   0.35},
    {"densitySustainRatio",  0.13,   0.22},
    {"densityHighFraction",  0.09,   0.25},
    {"densityRunFraction",   0.07,   0.25},
    {"activeMeasureFraction",0.05,   0.25},
}

local function rawChartShapeFeatures(steps, pn, song)
    local seconds = math.max(1, song:GetStepsSeconds())
    local peakNps = steps:GetPeakNps(pn) or 0

    local radar = steps:GetRadarValues(pn)
    local function radarValue(category)
        if not radar then return 0 end
        local value = radar:GetValue(category)
        return tonumber(value) or 0
    end

    local activeMeasures = 0
    local totalMeasures = 0
    local activeNpsSum = 0
    local highMeasures = 0
    local currentHighRun = 0
    local longestHighRun = 0

    if SLRecommendations.Config.StaminaDensityEnabled
        and steps.GetNpsPerMeasure
    then
        local npsPerMeasure =
            steps:GetNpsPerMeasure(pn) or {}

        totalMeasures = #npsPerMeasure

        local highThreshold =
            peakNps *
            SLRecommendations.Config.DensityHighThreshold

        for _, nps in ipairs(npsPerMeasure) do
            nps = tonumber(nps) or 0

            if nps > 0 then
                activeMeasures = activeMeasures + 1
                activeNpsSum = activeNpsSum + nps

                if peakNps > 0 and nps >= highThreshold then
                    highMeasures = highMeasures + 1
                    currentHighRun = currentHighRun + 1
                    longestHighRun =
                        math.max(
                            longestHighRun,
                            currentHighRun
                        )
                else
                    currentHighRun = 0
                end
            else
                currentHighRun = 0
            end
        end
    end

    local meanActiveNps =
        activeMeasures > 0
        and (activeNpsSum / activeMeasures)
        or 0

    local sustainRatio =
        peakNps > 0
        and clamp(meanActiveNps / peakNps, 0, 1)
        or 0

    local highFraction =
        activeMeasures > 0
        and clamp(highMeasures / activeMeasures, 0, 1)
        or 0

    local runFraction =
        activeMeasures > 0
        and clamp(longestHighRun / activeMeasures, 0, 1)
        or 0

    local activeFraction =
        totalMeasures > 0
        and clamp(activeMeasures / totalMeasures, 0, 1)
        or 0

    return {
        durationSeconds = seconds,
        logDuration = log1p(seconds),

        peakNps = peakNps,
        logPeakNps = log1p(peakNps),

        radarStream =
            radarValue("RadarCategory_Stream"),
        radarVoltage =
            radarValue("RadarCategory_Voltage"),
        radarAir =
            radarValue("RadarCategory_Air"),
        radarFreeze =
            radarValue("RadarCategory_Freeze"),
        radarChaos =
            radarValue("RadarCategory_Chaos"),

        densityMeanActiveNps = meanActiveNps,
        densitySustainRatio = sustainRatio,
        densityHighFraction = highFraction,
        densityRunFraction = runFraction,
        activeMeasureFraction = activeFraction,

        densityActiveMeasures = activeMeasures,
        densityTotalMeasures = totalMeasures,
        densityLongestHighRun = longestHighRun,
    }
end

local function getChartShapeFeatures(model, steps, song, group)
    if not model then
        return rawChartShapeFeatures(
            steps,
            PLAYER_1,
            song
        )
    end

    model.chartShapeCache =
        model.chartShapeCache or {}

    local key =
        group and group.key
        or (
            tostring(song:GetSongDir()) ..
            "|" ..
            tostring(steps)
        )

    local cached = model.chartShapeCache[key]
    if cached then return cached end

    local features =
        rawChartShapeFeatures(
            steps,
            model.pn,
            song
        )

    model.chartShapeCache[key] = features
    return features
end

local function staminaSimilarity(target, candidate)
    if not target or not candidate then return nil end

    local numerator = 0
    local denominator = 0

    for _, spec in ipairs(STAMINA_FEATURE_SPECS) do
        local name = spec[1]
        local weight = spec[2]
        local scale = spec[3]

        local a = tonumber(target[name])
        local b = tonumber(candidate[name])

        if a ~= nil and b ~= nil then
            local similarity =
                math.exp(
                    -math.abs(a - b) /
                    math.max(0.0001, scale)
                )

            numerator =
                numerator + similarity * weight
            denominator =
                denominator + weight
        end
    end

    if denominator <= 0 then return nil end
    return clamp(numerator / denominator, 0, 1)
end

local function addWeightedShape(target, shape, weight)
    for _, spec in ipairs(STAMINA_FEATURE_SPECS) do
        local name = spec[1]
        target[name] =
            (target[name] or 0) +
            (shape[name] or 0) * weight
    end
end

local function divideShape(target, divisor)
    if divisor <= 0 then return end

    for _, spec in ipairs(STAMINA_FEATURE_SPECS) do
        local name = spec[1]
        target[name] =
            (target[name] or 0) / divisor
    end
end

local function normalizeScoreName(name)
    name = trim(name):lower()
    name = name:gsub("%s+", " ")
    if name == "" then return nil end
    return name
end

local function maxValueInto(map, key, value)
    if not key or value == nil then return end
    if map[key] == nil or value > map[key] then
        map[key] = value
    end
end

local function getGroupBestPassedPercentDP(profile, group)
    if not profile or not group then return nil, 0 end

    local best = nil
    local excluded = 0

    for _, entry in ipairs(group.entries or {}) do
        local value, rejected =
            getBestPassedPercentDP(
                profile,
                entry.song,
                entry.steps
            )

        excluded = excluded + (rejected or 0)

        if value and (best == nil or value > best) then
            best = value
        end
    end

    return best, excluded
end

local function addProfileAlias(directory, identity, rawName)
    local name = normalizeScoreName(rawName)
    if not name then return end

    directory.aliasOwners[name] = directory.aliasOwners[name] or {}
    directory.aliasOwners[name][identity] = true
end

local function addProfileToPeerDirectory(directory, profile)
    if not profile or profileIsGuest(profile) then return end

    local guid = trim(profile:GetGUID() or "")
    if guid == "" then return end

    local identity = "guid:" .. guid
    if not directory.profilesByIdentity[identity] then
        directory.profilesByIdentity[identity] = profile
        directory.profileCount = directory.profileCount + 1
    end

    addProfileAlias(directory, identity, profile:GetDisplayName())
    addProfileAlias(directory, identity, profile:GetLastUsedHighScoreName())

    if profile.GetAllUsedHighScoreNames then
        for name in ivalues(profile:GetAllUsedHighScoreNames() or {}) do
            addProfileAlias(directory, identity, name)
        end
    end
end

local function buildPeerDirectory(currentProfile)
    local directory = {
        profilesByIdentity = {},
        aliasOwners = {},
        uniqueAliasToIdentity = {},
        profileCount = 0,
        profileGuidBindingSeen = nil,
    }

    for profileID in ivalues(PROFILEMAN:GetLocalProfileIDs() or {}) do
        addProfileToPeerDirectory(
            directory,
            PROFILEMAN:GetLocalProfile(profileID)
        )
    end

    -- The active profile can be a USB/memory-card profile and therefore not
    -- appear in GetLocalProfileIDs().
    addProfileToPeerDirectory(directory, currentProfile)

    for alias, owners in pairs(directory.aliasOwners) do
        local only = nil
        local count = 0

        for identity in pairs(owners) do
            only = identity
            count = count + 1
            if count > 1 then break end
        end

        if count == 1 then
            directory.uniqueAliasToIdentity[alias] = only
        end
    end

    return directory
end

local function machineHighScoreIdentity(directory, highScore)
    if not highScore then return nil, "none" end

    -- v10's optional engine binding exposes HighScore::GetPlayerGuid(), the
    -- scalar GUID persisted on ordinary scores.  Older builds simply do not
    -- have this method, and the code below falls back to score names.
    if highScore.GetProfileGuid then
        directory.profileGuidBindingSeen = true

        local guid = trim(highScore:GetProfileGuid() or "")
        if guid ~= "" then
            return "guid:" .. guid, "guid"
        end
    elseif directory.profileGuidBindingSeen == nil then
        directory.profileGuidBindingSeen = false
    end

    local name = normalizeScoreName(highScore:GetName())
    if not name then return nil, "none" end

    -- If this score name is known to belong to exactly one local profile,
    -- promote it to that profile's GUID identity.  Ambiguous aliases remain
    -- name-only rather than guessing.
    local localIdentity = directory.uniqueAliasToIdentity[name]
    if localIdentity then
        return localIdentity, "name->profile"
    end

    return "name:" .. name, "name"
end

local function collectPeerScoresForGroup(model, group)
    local scores = {}
    local identitySources = {}

    -- Local profiles provide complete profile-local score history, not merely
    -- whatever survived the machine leaderboard cap.
    for identity, profile in pairs(model.localPeerDirectory.profilesByIdentity) do
        local dp, excluded =
            getGroupBestPassedPercentDP(profile, group)

        model.localPeerExcludedNonPassScores =
            model.localPeerExcludedNonPassScores +
            (excluded or 0)

        if dp then
            maxValueInto(scores, identity, dp)
            identitySources[identity] = "profile"
        end
    end

    -- Machine scores add guests, USB profiles, and other identities not
    -- represented by a currently-installed local profile.  Duplicate chart
    -- installs are merged by identity using the best observed score.
    local machine = PROFILEMAN:GetMachineProfile()

    for _, entry in ipairs(group.entries or {}) do
        local hsl = getHSL(machine, entry.song, entry.steps)
        if hsl then
            for highScore in ivalues(hsl:GetHighScores() or {}) do
                if isPassedHighScore(highScore) then
                    local identity, source =
                        machineHighScoreIdentity(
                            model.localPeerDirectory,
                            highScore
                        )

                    if identity then
                        local dp = highScore:GetPercentDP()
                        if dp then
                            maxValueInto(scores, identity, dp)

                            if not identitySources[identity]
                                or identitySources[identity] ~= "profile"
                            then
                                identitySources[identity] = source
                            end
                        end
                    end
                else
                    model.localPeerExcludedNonPassScores =
                        model.localPeerExcludedNonPassScores + 1
                end
            end
        end
    end

    return scores, identitySources
end

local function calculatePeerStat(model, group)
    if not SLRecommendations.Config.LocalPeerEnabled then return nil end
    if not model.usePersonalData or not model.profile then return nil end

    local currentGuid = trim(model.profile:GetGUID() or "")
    if currentGuid == "" then return nil end

    local currentIdentity = "guid:" .. currentGuid
    local scores, sources = collectPeerScoresForGroup(model, group)

    -- collectPeerScoresForGroup() already included the active profile and
    -- counted its excluded non-pass scores.  Reuse that value instead of
    -- scanning/counting the active profile a second time.
    local playerScore = scores[currentIdentity]

    if not playerScore then
        model.localPeerFailedOnlyCharts =
            model.localPeerFailedOnlyCharts + 1
        return nil
    end

    sources[currentIdentity] = "current-profile"

    local opponents = {}
    local less = 0
    local ties = 0
    local uniqueGuidOpponents = 0
    local uniqueNameOnlyOpponents = 0

    for identity, score in pairs(scores) do
        if identity ~= currentIdentity then
            opponents[#opponents + 1] = score

            if score < playerScore - 0.0000001 then
                less = less + 1
            elseif math.abs(score - playerScore) <= 0.0000001 then
                ties = ties + 1
            end

            if identity:sub(1, 5) == "guid:" then
                uniqueGuidOpponents = uniqueGuidOpponents + 1
            else
                uniqueNameOnlyOpponents =
                    uniqueNameOnlyOpponents + 1
            end

            model.localPeerObservedIdentities[identity] = true
        end
    end

    if #opponents == 0 then return nil end

    local opponentMedian = median(opponents)
    local percentile =
        (less + ties * 0.5) / #opponents

    local gap = playerScore - opponentMedian
    local gapScale =
        math.max(0.0001, SLRecommendations.Config.LocalPeerGapScale)

    -- Logistic mapping keeps very large score gaps bounded while preserving
    -- whether the player is above/below the local field.
    local marginScore =
        1 / (1 + math.exp(-gap / gapScale))

    local rawRelative =
        percentile * 0.65 +
        marginScore * 0.35

    local confidence = clamp(
        #opponents /
            SLRecommendations.Config.LocalPeerFullConfidenceOpponents,
        0,
        1
    )

    -- Sparse charts shrink toward neutral rather than allowing one rival to
    -- define the player's entire performance model.
    local relative =
        0.5 + (rawRelative - 0.5) * confidence

    return {
        playerScore = playerScore,
        opponents = #opponents,
        opponentMedian = opponentMedian,
        percentile = percentile,
        gap = gap,
        marginScore = marginScore,
        confidence = confidence,
        relative = relative,
        guidOpponents = uniqueGuidOpponents,
        nameOnlyOpponents = uniqueNameOnlyOpponents,

        -- Retained for the machine-local two-way scoring model.  These are
        -- passed-score-only, already deduped to one best score per identity.
        allScores = scores,
        identitySources = sources,
    }
end

local function localPeerRawFeatures(meter, shape, tech)
    shape = shape or {}

    local safeMeter =
        math.max(0, tonumber(meter) or 0)

    local values = {
        log1p(safeMeter),

        tonumber(shape.logDuration) or 0,
        tonumber(shape.logPeakNps) or 0,

        tonumber(shape.radarStream) or 0,
        tonumber(shape.radarVoltage) or 0,
        tonumber(shape.radarAir) or 0,
        tonumber(shape.radarFreeze) or 0,
        tonumber(shape.radarChaos) or 0,

        tonumber(shape.densitySustainRatio) or 0,
        tonumber(shape.densityHighFraction) or 0,
        tonumber(shape.densityRunFraction) or 0,
        tonumber(shape.activeMeasureFraction) or 0,
    }

    for i = 1, #TECH_CATEGORIES do
        values[#values + 1] =
            log1p(
                tech and tonumber(tech[i]) or 0
            )
    end

    return values
end

local function solveLinearSystem(matrix, vector)
    local n = #vector

    -- Gauss-Jordan elimination with partial pivoting.  This matrix is tiny
    -- (intercept + meter + NPS + tech features), so the straightforward
    -- implementation is more than sufficient and only runs once per model.
    for col = 1, n do
        local pivotRow = col
        local pivotAbs =
            math.abs(matrix[col][col] or 0)

        for row = col + 1, n do
            local value =
                math.abs(matrix[row][col] or 0)

            if value > pivotAbs then
                pivotAbs = value
                pivotRow = row
            end
        end

        if pivotAbs < 0.000000001 then
            return nil
        end

        if pivotRow ~= col then
            matrix[col], matrix[pivotRow] =
                matrix[pivotRow], matrix[col]

            vector[col], vector[pivotRow] =
                vector[pivotRow], vector[col]
        end

        local pivot = matrix[col][col]

        for j = col, n do
            matrix[col][j] =
                matrix[col][j] / pivot
        end

        vector[col] = vector[col] / pivot

        for row = 1, n do
            if row ~= col then
                local factor = matrix[row][col]

                if math.abs(factor) > 0.000000001 then
                    for j = col, n do
                        matrix[row][j] =
                            matrix[row][j] -
                            factor * matrix[col][j]
                    end

                    vector[row] =
                        vector[row] -
                        factor * vector[col]
                end
            end
        end
    end

    return vector
end

local function fitLocalPeerRegression(model)
    local examples = model.localPeerExamples or {}

    if #examples <
        SLRecommendations.Config.LocalPeerRegressionMinExamples
    then
        return nil
    end

    local rawFeatures = {}
    local featureCount = nil
    local totalWeight = 0

    for i, example in ipairs(examples) do
        local features =
            localPeerRawFeatures(
                example.meter,
                example.shape,
                example.tech
            )

        rawFeatures[i] = features
        featureCount = featureCount or #features
        totalWeight =
            totalWeight +
            math.max(0.05, example.confidence or 0)
    end

    if not featureCount or totalWeight <= 0 then
        return nil
    end

    local means = {}
    local stds = {}

    for j = 1, featureCount do
        local sum = 0

        for i, example in ipairs(examples) do
            local weight =
                math.max(
                    0.05,
                    example.confidence or 0
                )

            sum =
                sum +
                rawFeatures[i][j] * weight
        end

        means[j] = sum / totalWeight
    end

    for j = 1, featureCount do
        local variance = 0

        for i, example in ipairs(examples) do
            local weight =
                math.max(
                    0.05,
                    example.confidence or 0
                )

            local delta =
                rawFeatures[i][j] - means[j]

            variance =
                variance +
                delta * delta * weight
        end

        stds[j] =
            math.sqrt(variance / totalWeight)

        if stds[j] < 0.000001 then
            stds[j] = 1
        end
    end

    local dimension = featureCount + 1
    local matrix = {}
    local vector = {}

    for row = 1, dimension do
        matrix[row] = {}
        vector[row] = 0

        for col = 1, dimension do
            matrix[row][col] = 0
        end
    end

    for i, example in ipairs(examples) do
        local x = {1}

        for j = 1, featureCount do
            x[j + 1] =
                (rawFeatures[i][j] - means[j]) /
                stds[j]
        end

        local weight =
            math.max(
                0.05,
                example.confidence or 0
            )

        local y = example.relative

        for row = 1, dimension do
            vector[row] =
                vector[row] +
                weight * x[row] * y

            for col = 1, dimension do
                matrix[row][col] =
                    matrix[row][col] +
                    weight * x[row] * x[col]
            end
        end
    end

    local ridge =
        math.max(
            0,
            SLRecommendations.Config.LocalPeerRegressionRidge
        )

    -- Do not meaningfully penalize the intercept.
    matrix[1][1] = matrix[1][1] + 0.0001

    for i = 2, dimension do
        matrix[i][i] =
            matrix[i][i] + ridge
    end

    local coefficients =
        solveLinearSystem(matrix, vector)

    if not coefficients then return nil end

    local squaredError = 0
    local errorWeight = 0

    for i, example in ipairs(examples) do
        local prediction = coefficients[1]

        for j = 1, featureCount do
            local z =
                (rawFeatures[i][j] - means[j]) /
                stds[j]

            prediction =
                prediction +
                coefficients[j + 1] * z
        end

        prediction = clamp(prediction, 0, 1)

        local weight =
            math.max(
                0.05,
                example.confidence or 0
            )

        local error =
            prediction - example.relative

        squaredError =
            squaredError +
            error * error * weight

        errorWeight = errorWeight + weight
    end

    local rmse =
        errorWeight > 0
        and math.sqrt(squaredError / errorWeight)
        or 1

    local globalConfidence =
        clamp(#examples / 100, 0, 1) *
        clamp(1 - rmse / 0.35, 0.25, 1)

    return {
        means = means,
        stds = stds,
        coefficients = coefficients,
        featureCount = featureCount,
        examples = #examples,
        rmse = rmse,
        globalConfidence = globalConfidence,
    }
end

local function predictLocalPeerPerformance(model, song, steps, group)
    if not SLRecommendations.Config.LocalPeerEnabled then
        return nil
    end

    -- Direct evidence on this exact chart remains the strongest signal.
    local direct =
        group and model.localPeerByGroupKey[group.key] or nil

    if direct and
        direct.opponents >=
            SLRecommendations.Config.LocalPeerMinOpponents
    then
        return {
            fit = direct.relative,
            raw = direct.relative,
            confidence = direct.confidence,
            source = "direct",
            opponents = direct.opponents,
            percentile = direct.percentile,
            gap = direct.gap,
            neighbors = 0,
        }
    end

    local regression = model.localPeerRegression
    if not regression then return nil end

    local shape =
        getChartShapeFeatures(
            model,
            steps,
            song,
            group
        )

    local rawFeatures =
        localPeerRawFeatures(
            steps:GetMeter(),
            shape,
            getTechVector(
                steps,
                model.pn,
                song
            )
        )

    local prediction =
        regression.coefficients[1]

    local maxAbsZ = 0

    for j = 1, regression.featureCount do
        local z =
            (rawFeatures[j] - regression.means[j]) /
            regression.stds[j]

        maxAbsZ =
            math.max(maxAbsZ, math.abs(z))

        prediction =
            prediction +
            regression.coefficients[j + 1] * z
    end

    prediction = clamp(prediction, 0, 1)

    -- Extrapolation far outside the player's training data shrinks toward
    -- neutral.  This keeps the regression from being overconfident on unusual
    -- charts.
    local extrapolation =
        math.max(0, maxAbsZ - 2.5)

    local confidence =
        regression.globalConfidence *
        math.exp(-0.35 * extrapolation)

    confidence = clamp(confidence, 0, 1)

    return {
        fit =
            0.5 +
            (prediction - 0.5) * confidence,
        raw = prediction,
        confidence = confidence,
        source = "regression",
        opponents = nil,
        percentile = nil,
        gap = nil,
        neighbors = 0,
        maxAbsZ = maxAbsZ,
    }
end


local function scoringQualityFromPercentDP(dp)
    if dp == nil then return nil end

    -- PercentDP bunches tightly near 100%.  Modeling "missing score" on a log
    -- scale gives useful separation between, say, 90%, 97%, 99%, and 99.7%.
    local missing =
        clamp(1 - tonumber(dp), 0.001, 0.75)

    return -math.log(missing)
end

local function percentDPFromScoringQuality(quality)
    if quality == nil then return nil end

    return clamp(
        1 - math.exp(-math.max(0, quality)),
        0,
        0.999
    )
end


local function robustCenterScale(values)
    if not values or #values == 0 then
        return nil, nil
    end

    local center = median(values)
    if center == nil then return nil, nil end

    local deviations = {}
    for i, value in ipairs(values) do
        deviations[i] = math.abs(value - center)
    end

    local mad = median(deviations) or 0

    -- Convert MAD to an approximately standard-deviation-like scale.
    local scale = math.max(0.10, mad * 1.4826)

    return center, scale
end

local function scoringDifficultyToEase(
    difficulty,
    confidence,
    center,
    scale
)
    if difficulty == nil then return nil end

    center = center or 0
    scale = math.max(0.10, scale or 0.25)

    local z = (difficulty - center) / scale

    -- Lower chart difficulty => higher ease.
    local rawEase = 1 / (1 + math.exp(z))

    confidence = clamp(confidence or 0, 0, 1)

    -- Sparse/regressed values shrink to neutral.
    return 0.5 + (rawEase - 0.5) * confidence,
        rawEase,
        z
end

local function localScoreSourceWeight(source)
    if source == "current-profile"
        or source == "profile"
    then
        return 1.00
    elseif source == "guid"
        or source == "name->profile"
    then
        return 0.80
    elseif source == "name" then
        return 0.55
    end

    return 0.50
end

local function fitLocalScoringDifficulty(model)
    if not SLRecommendations.Config.LocalScoringDifficultyEnabled then
        return nil
    end

    local observations = {}
    local byPlayer = {}
    local byChart = {}
    local chartMeta = {}

    for _, example in ipairs(model.localPeerExamples or {}) do
        local stat =
            model.localPeerByGroupKey[example.key]

        if stat
            and stat.allScores
            and stat.opponents + 1 >=
                SLRecommendations.Config.LocalScoringDifficultyMinPlayersPerChart
        then
            local chartObservationCount = 0

            for identity, dp in pairs(stat.allScores) do
                local quality =
                    scoringQualityFromPercentDP(dp)

                if quality then
                    local source =
                        stat.identitySources
                        and stat.identitySources[identity]
                        or "name"

                    local observation = {
                        player = identity,
                        chart = example.key,
                        dp = dp,
                        quality = quality,
                        weight =
                            localScoreSourceWeight(source),
                        source = source,
                    }

                    observations[#observations + 1] =
                        observation

                    byPlayer[identity] =
                        byPlayer[identity] or {}

                    byPlayer[identity][
                        #byPlayer[identity] + 1
                    ] = observation

                    byChart[example.key] =
                        byChart[example.key] or {}

                    byChart[example.key][
                        #byChart[example.key] + 1
                    ] = observation

                    chartObservationCount =
                        chartObservationCount + 1
                end
            end

            if chartObservationCount >=
                SLRecommendations.Config.LocalScoringDifficultyMinPlayersPerChart
            then
                chartMeta[example.key] = example
            end
        end
    end

    if #observations == 0 then return nil end

    -- Drop identities seen on too few charts.  A one-off guest score can help
    -- a chart's leaderboard comparison, but it should not be assigned a
    -- standalone latent "player ability" term.
    local allowedPlayers = {}

    for identity, rows in pairs(byPlayer) do
        local uniqueCharts = {}
        local count = 0

        for _, row in ipairs(rows) do
            if not uniqueCharts[row.chart] then
                uniqueCharts[row.chart] = true
                count = count + 1
            end
        end

        if count >=
            SLRecommendations.Config.LocalScoringDifficultyMinChartsPerPlayer
        then
            allowedPlayers[identity] = true
        end
    end

    local filtered = {}
    byPlayer = {}
    byChart = {}

    for _, observation in ipairs(observations) do
        if allowedPlayers[observation.player] then
            filtered[#filtered + 1] = observation

            byPlayer[observation.player] =
                byPlayer[observation.player] or {}

            byPlayer[observation.player][
                #byPlayer[observation.player] + 1
            ] = observation

            byChart[observation.chart] =
                byChart[observation.chart] or {}

            byChart[observation.chart][
                #byChart[observation.chart] + 1
            ] = observation
        end
    end

    observations = filtered
    if #observations == 0 then return nil end

    -- Drop charts that no longer have enough distinct retained players after
    -- filtering sparse identities.
    local allowedCharts = {}

    for chartKey, rows in pairs(byChart) do
        local identities = {}
        local count = 0

        for _, row in ipairs(rows) do
            if not identities[row.player] then
                identities[row.player] = true
                count = count + 1
            end
        end

        if count >=
            SLRecommendations.Config.LocalScoringDifficultyMinPlayersPerChart
        then
            allowedCharts[chartKey] = true
        end
    end

    filtered = {}
    byPlayer = {}
    byChart = {}

    local totalQuality = 0
    local totalWeight = 0

    for _, observation in ipairs(observations) do
        if allowedCharts[observation.chart] then
            filtered[#filtered + 1] = observation

            byPlayer[observation.player] =
                byPlayer[observation.player] or {}

            byPlayer[observation.player][
                #byPlayer[observation.player] + 1
            ] = observation

            byChart[observation.chart] =
                byChart[observation.chart] or {}

            byChart[observation.chart][
                #byChart[observation.chart] + 1
            ] = observation

            totalQuality =
                totalQuality +
                observation.quality *
                observation.weight

            totalWeight =
                totalWeight +
                observation.weight
        end
    end

    observations = filtered
    if #observations == 0 or totalWeight <= 0 then
        return nil
    end

    local baseline =
        totalQuality / totalWeight

    local abilities = {}
    local difficulties = {}

    for identity in pairs(byPlayer) do
        abilities[identity] = 0
    end

    for chartKey in pairs(byChart) do
        difficulties[chartKey] = 0
    end

    local playerRidge =
        SLRecommendations.Config.LocalScoringDifficultyPlayerRidge

    local chartRidge =
        SLRecommendations.Config.LocalScoringDifficultyChartRidge

    for _ = 1,
        SLRecommendations.Config.LocalScoringDifficultyIterations
    do
        -- Player ability update.
        for identity, rows in pairs(byPlayer) do
            local numerator = 0
            local denominator = playerRidge

            for _, row in ipairs(rows) do
                local weight = row.weight
                numerator =
                    numerator +
                    weight *
                    (
                        row.quality -
                        baseline +
                        (difficulties[row.chart] or 0)
                    )

                denominator =
                    denominator + weight
            end

            abilities[identity] =
                denominator > 0
                and numerator / denominator
                or 0
        end

        -- Center player ability at zero and move the offset into baseline.
        local abilitySum = 0
        local abilityWeight = 0

        for identity, rows in pairs(byPlayer) do
            local weight = #rows
            abilitySum =
                abilitySum +
                (abilities[identity] or 0) * weight
            abilityWeight =
                abilityWeight + weight
        end

        if abilityWeight > 0 then
            local center =
                abilitySum / abilityWeight

            for identity in pairs(abilities) do
                abilities[identity] =
                    abilities[identity] - center
            end

            baseline = baseline + center
        end

        -- Chart scoring-difficulty update.
        for chartKey, rows in pairs(byChart) do
            local numerator = 0
            local denominator = chartRidge

            for _, row in ipairs(rows) do
                local weight = row.weight

                numerator =
                    numerator +
                    weight *
                    (
                        baseline +
                        (abilities[row.player] or 0) -
                        row.quality
                    )

                denominator =
                    denominator + weight
            end

            difficulties[chartKey] =
                denominator > 0
                and numerator / denominator
                or 0
        end

        -- Center chart difficulty at zero and shift baseline accordingly.
        local difficultySum = 0
        local difficultyWeight = 0

        for chartKey, rows in pairs(byChart) do
            local weight = #rows
            difficultySum =
                difficultySum +
                (difficulties[chartKey] or 0) * weight
            difficultyWeight =
                difficultyWeight + weight
        end

        if difficultyWeight > 0 then
            local center =
                difficultySum / difficultyWeight

            for chartKey in pairs(difficulties) do
                difficulties[chartKey] =
                    difficulties[chartKey] - center
            end

            baseline = baseline - center
        end
    end

    local squaredQualityError = 0
    local squaredDpError = 0
    local errorWeight = 0

    for _, row in ipairs(observations) do
        local predictedQuality =
            baseline +
            (abilities[row.player] or 0) -
            (difficulties[row.chart] or 0)

        local predictedDp =
            percentDPFromScoringQuality(
                predictedQuality
            )

        local qualityError =
            predictedQuality - row.quality

        local dpError =
            predictedDp - row.dp

        squaredQualityError =
            squaredQualityError +
            qualityError * qualityError * row.weight

        squaredDpError =
            squaredDpError +
            dpError * dpError * row.weight

        errorWeight =
            errorWeight + row.weight
    end

    local playerCount = 0
    for _ in pairs(byPlayer) do
        playerCount = playerCount + 1
    end

    local chartCount = 0
    for _ in pairs(byChart) do
        chartCount = chartCount + 1
    end

    local currentGuid =
        trim(model.profile:GetGUID() or "")

    local currentIdentity =
        currentGuid ~= ""
        and ("guid:" .. currentGuid)
        or nil

    local difficultyValues = {}
    for _, value in pairs(difficulties) do
        difficultyValues[#difficultyValues + 1] = value
    end

    local difficultyCenter, difficultyScale =
        robustCenterScale(difficultyValues)

    local result = {
        baseline = baseline,
        baselineDp =
            percentDPFromScoringQuality(baseline),

        abilities = abilities,
        difficulties = difficulties,
        difficultyCenter = difficultyCenter or 0,
        difficultyScale = difficultyScale or 0.25,
        byChart = byChart,
        chartMeta = chartMeta,

        currentIdentity = currentIdentity,
        currentAbility =
            currentIdentity
            and abilities[currentIdentity]
            or nil,

        observations = #observations,
        players = playerCount,
        charts = chartCount,

        qualityRmse =
            errorWeight > 0
            and math.sqrt(
                squaredQualityError / errorWeight
            )
            or nil,

        dpRmse =
            errorWeight > 0
            and math.sqrt(
                squaredDpError / errorWeight
            )
            or nil,
    }

    if result.currentAbility then
        result.currentBaselineExpectedDp =
            percentDPFromScoringQuality(
                baseline +
                result.currentAbility
            )
    end

    return result
end

local function fitLocalScoringDifficultyRegression(model)
    local localModel = model.localScoringDifficulty
    if not localModel then return nil end

    local rows = {}

    for _, example in ipairs(model.localPeerExamples or {}) do
        local target =
            localModel.difficulties[example.key]

        if target ~= nil then
            rows[#rows + 1] = {
                features =
                    localPeerRawFeatures(
                        example.meter,
                        example.shape,
                        example.tech
                    ),
                target = target,
                weight =
                    math.min(
                        1,
                        (
                            #(
                                localModel.byChart[
                                    example.key
                                ] or {}
                            )
                        ) / 5
                    ),
            }
        end
    end

    if #rows < 20 then return nil end

    local featureCount = #rows[1].features
    local means = {}
    local stds = {}
    local totalWeight = 0

    for _, row in ipairs(rows) do
        totalWeight =
            totalWeight +
            math.max(0.1, row.weight)
    end

    for j = 1, featureCount do
        local total = 0

        for _, row in ipairs(rows) do
            local weight =
                math.max(0.1, row.weight)

            total =
                total +
                row.features[j] * weight
        end

        means[j] = total / totalWeight
    end

    for j = 1, featureCount do
        local variance = 0

        for _, row in ipairs(rows) do
            local weight =
                math.max(0.1, row.weight)

            local delta =
                row.features[j] - means[j]

            variance =
                variance +
                delta * delta * weight
        end

        stds[j] =
            math.sqrt(variance / totalWeight)

        if stds[j] < 0.000001 then
            stds[j] = 1
        end
    end

    local dimension = featureCount + 1
    local matrix = {}
    local vector = {}

    for r = 1, dimension do
        matrix[r] = {}
        vector[r] = 0

        for c = 1, dimension do
            matrix[r][c] = 0
        end
    end

    for _, row in ipairs(rows) do
        local x = {1}

        for j = 1, featureCount do
            x[j + 1] =
                (row.features[j] - means[j]) /
                stds[j]
        end

        local weight =
            math.max(0.1, row.weight)

        for r = 1, dimension do
            vector[r] =
                vector[r] +
                weight * x[r] * row.target

            for c = 1, dimension do
                matrix[r][c] =
                    matrix[r][c] +
                    weight * x[r] * x[c]
            end
        end
    end

    matrix[1][1] = matrix[1][1] + 0.0001

    local ridge =
        SLRecommendations.Config.LocalScoringDifficultyRegressionRidge

    for i = 2, dimension do
        matrix[i][i] =
            matrix[i][i] + ridge
    end

    local coefficients =
        solveLinearSystem(matrix, vector)

    if not coefficients then return nil end

    local squaredError = 0
    local errorWeight = 0

    for _, row in ipairs(rows) do
        local prediction =
            coefficients[1]

        for j = 1, featureCount do
            prediction =
                prediction +
                coefficients[j + 1] *
                (
                    (row.features[j] - means[j]) /
                    stds[j]
                )
        end

        local error =
            prediction - row.target

        local weight =
            math.max(0.1, row.weight)

        squaredError =
            squaredError +
            error * error * weight

        errorWeight =
            errorWeight + weight
    end

    local rmse =
        errorWeight > 0
        and math.sqrt(squaredError / errorWeight)
        or nil

    local confidence =
        clamp(#rows / 100, 0, 1)

    if rmse then
        confidence =
            confidence *
            clamp(1 - rmse / 0.75, 0.20, 1)
    end

    return {
        means = means,
        stds = stds,
        coefficients = coefficients,
        featureCount = featureCount,
        examples = #rows,
        rmse = rmse,
        confidence = confidence,
    }
end

local function predictLocalScoringForChart(
    model,
    song,
    steps,
    group
)
    local localModel = model.localScoringDifficulty

    if not localModel
        or localModel.currentAbility == nil
    then
        return nil
    end

    local difficulty = nil
    local source = nil
    local confidence = nil

    if group
        and localModel.difficulties[group.key] ~= nil
    then
        difficulty =
            localModel.difficulties[group.key]

        local rows =
            localModel.byChart[group.key] or {}

        confidence =
            clamp(#rows / 5, 0, 1)

        source = "direct"
    else
        local regression =
            model.localScoringDifficultyRegression

        if not regression then return nil end

        local shape =
            getChartShapeFeatures(
                model,
                steps,
                song,
                group
            )

        local features =
            localPeerRawFeatures(
                steps:GetMeter(),
                shape,
                getTechVector(
                    steps,
                    model.pn,
                    song
                )
            )

        difficulty =
            regression.coefficients[1]

        local maxAbsZ = 0

        for j = 1, regression.featureCount do
            local z =
                (features[j] - regression.means[j]) /
                regression.stds[j]

            maxAbsZ =
                math.max(
                    maxAbsZ,
                    math.abs(z)
                )

            difficulty =
                difficulty +
                regression.coefficients[j + 1] * z
        end

        confidence =
            regression.confidence *
            math.exp(
                -0.35 *
                math.max(0, maxAbsZ - 2.5)
            )

        confidence =
            clamp(confidence, 0, 1)

        source = "regression"
    end

    local expectedQuality =
        localModel.baseline +
        localModel.currentAbility -
        difficulty

    local expectedDp =
        percentDPFromScoringQuality(
            expectedQuality
        )

    -- Confidence-shrunk expected score.  Sparse/direct or extrapolated
    -- predictions move toward the player's baseline expectation.
    local baselineDp =
        localModel.currentBaselineExpectedDp
        or localModel.baselineDp
        or expectedDp

    local shrunkExpectedDp =
        baselineDp +
        (expectedDp - baselineDp) *
        confidence

    local ease, rawEase, difficultyZ =
        scoringDifficultyToEase(
            difficulty,
            confidence,
            localModel.difficultyCenter,
            localModel.difficultyScale
        )

    return {
        difficulty = difficulty,
        expectedDp = expectedDp,
        shrunkExpectedDp = shrunkExpectedDp,
        confidence = confidence,
        source = source,

        ease = ease or 0.5,
        rawEase = rawEase or 0.5,
        difficultyZ = difficultyZ or 0,
    }
end

local function normalizeMap(map)
    local maxValue = 0
    for _, v in pairs(map) do
        maxValue = math.max(maxValue, v)
    end

    if maxValue <= 0 then return map end
    for k, v in pairs(map) do
        map[k] = v / maxValue
    end
    return map
end

local function addWeighted(map, rawKey, weight, normalizer)
    local key = (normalizer or normalizeMetadata)(rawKey)
    if not key then return end
    map[key] = (map[key] or 0) + weight
end

local function getMapAffinity(map, rawKey, normalizer)
    local key = (normalizer or normalizeMetadata)(rawKey)
    if not key then return nil end
    return map[key] or 0
end

local function scoreMetadata(model, song, steps)
    local weightedSum = 0
    local weightSum = 0

    local artist = getMapAffinity(model.artistAffinity, song:GetDisplayArtist())
    if artist ~= nil then
        weightedSum = weightedSum + artist * 0.40
        weightSum = weightSum + 0.40
    end

    local genre = getMapAffinity(model.genreAffinity, song:GetGenre())
    if genre ~= nil then
        weightedSum = weightedSum + genre * 0.20
        weightSum = weightSum + 0.20
    end

    local credit = getMapAffinity(model.creditAffinity, steps:GetAuthorCredit(), normalizeCredit)
    if credit ~= nil then
        weightedSum = weightedSum + credit * 0.40
        weightSum = weightSum + 0.40
    end

    if weightSum <= 0 then return 0 end
    return clamp(weightedSum / weightSum, 0, 1)
end

local function weightedQuantile(samples, q)
    if #samples == 0 then return nil end

    table.sort(samples, function(a, b)
        if a.value == b.value then return a.weight < b.weight end
        return a.value < b.value
    end)

    local total = 0
    for _, sample in ipairs(samples) do
        total = total + sample.weight
    end
    if total <= 0 then return nil end

    local target = total * clamp(q, 0, 1)
    local cumulative = 0
    for _, sample in ipairs(samples) do
        cumulative = cumulative + sample.weight
        if cumulative >= target then
            return sample.value
        end
    end

    return samples[#samples].value
end

local function ensureSkillMeterStat(model, meter)
    local stat = model.skillByMeter[meter]
    if not stat then
        stat = {count = 0, decent = 0, strong = 0, scores = {}}
        model.skillByMeter[meter] = stat
    end
    return stat
end

local function ensureTechStat(model, feature)
    local stat = model.techMastery[feature]
    if not stat then
        stat = {
            qualifying = 0,
            strong = 0,
            scores = {},
            mastered = false,
            familiarity = 0,
            recentWeight = 0,
            recentCharts = 0,
            recentInterest = 0,
            meterWeights = {},
            meterWeightTotal = 0,
        }
        model.techMastery[feature] = stat
    end
    return stat
end

local function finalizeSkillAndTechProfile(model)
    local cfg = curriculum()
    local skillCfg = cfg.Skill or DEFAULT_CURRICULUM.Skill
    local jokeMax = cfg.JokeMeterMax or 30

    if not model.usePersonalData or model.passedHistoryCharts <= 0 then
        model.personalConfidence = 0
        model.playerMaturity = model.profileIsGuest and "guest" or "cold"
        model.targetMeter = SLRecommendations.Config.ColdStartDefaultMeter
        model.difficultySigma = SLRecommendations.Config.ColdStartDifficultySigma
        model.skillFocusLevel = nil
        model.scoreWellReady = false
        return
    end

    local highestPass, highestReliable, highestMastered = nil, nil, nil
    for meter, stat in pairs(model.skillByMeter) do
        if meter >= 1 and meter <= jokeMax then
            stat.median = median(stat.scores)
            if stat.count > 0 then
                highestPass = math.max(highestPass or meter, meter)
            end
            if stat.count >= (skillCfg.reliableMinCharts or 2)
                and stat.median and stat.median >= (skillCfg.decentDP or 0.80)
            then
                highestReliable = math.max(highestReliable or meter, meter)
            end
            local mastered = stat.decent >= (skillCfg.masteryMinCharts or 4)
                or stat.strong >= (skillCfg.strongMasteryMinCharts or 3)
            if mastered then
                highestMastered = math.max(highestMastered or meter, meter)
            end
        end
    end

    model.workingMeter = highestPass
    model.reliableMeter = highestReliable
    model.masteredMeter = highestMastered
    model.skillComfortMeter = highestReliable or highestMastered or highestPass

    local confidence = clamp(
        model.passedHistoryCharts / SLRecommendations.Config.PersonalConfidenceFullPassedCharts,
        0, 1
    )
    if (highestPass or 0) >= 11 then confidence = math.max(confidence, 0.65) end
    if (highestMastered or 0) >= 11 then confidence = math.max(confidence, 0.85) end
    model.personalConfidence = confidence

    if (highestMastered or 0) >= 11
        or ((highestPass or 0) >= 11 and model.passedHistoryCharts >= 10)
    then
        model.playerMaturity = "established"
    elseif model.passedHistoryCharts < 3 then
        model.playerMaturity = "cold"
    else
        model.playerMaturity = "developing"
    end

    if model.playerMaturity ~= "established" and model.skillComfortMeter then
        model.targetMeter = model.skillComfortMeter
        model.difficultySigma = math.max(1.25, math.min(model.difficultySigma, 2.0))
    end

    local progressionBase = highestMastered or highestReliable or highestPass
    if progressionBase then
        if highestMastered or highestReliable then
            model.levelUpMeter = math.min(jokeMax, progressionBase + 1)
        else
            model.levelUpMeter = math.min(jokeMax, progressionBase)
        end
    end
    model.skillFocusLevel = model.levelUpMeter or model.skillComfortMeter

    -- Tech mastery + recent-interest normalization.
    local maxRecent = 0
    for feature, spec in pairs(cfg.Tech or {}) do
        local stat = ensureTechStat(model, feature)
        stat.median = median(stat.scores)
        local minCharts = tonumber(spec.masteryMinCharts) or 4
        local masteryDP = tonumber(spec.masteryDP) or 0.85
        stat.mastered = stat.qualifying >= minCharts
            and stat.median ~= nil and stat.median >= masteryDP
        stat.familiarity = clamp(stat.qualifying / math.max(1, minCharts), 0, 1)
        maxRecent = math.max(maxRecent, stat.recentWeight)
    end

    if maxRecent > 0 then
        for _, stat in pairs(model.techMastery) do
            stat.recentInterest = clamp(stat.recentWeight / maxRecent, 0, 1)
        end
    end

    model.scoreWellReady = model.localPeerBenchmarkCharts >= SLRecommendations.Config.ScoreWellMinBenchmarkCharts
        and model.personalConfidence >= 0.25
end

local COLD_FOR_YOU_WEIGHTS = {
    difficulty = 0.28,
    popularity = 0.22,
    machineRecentActivity = 0.15,
    communityFavorite = 0.15,
    communityScoreability = 0.08,
    beginnerSafety = 0.07,
    exploration = 0.05,
}

local COLD_LIKE_WEIGHTS = {
    difficulty = 0.15,
    popularity = 0.20,
    machineRecentActivity = 0.12,
    communityFavorite = 0.35,
    communityScoreability = 0.08,
    beginnerSafety = 0.10,
}

local function blendWeights(a, b, t)
    t = clamp(t or 0, 0, 1)
    local keys, result = {}, {}
    for key in pairs(a or {}) do keys[key] = true end
    for key in pairs(b or {}) do keys[key] = true end
    for key in pairs(keys) do
        result[key] = (a and a[key] or 0) * (1 - t) + (b and b[key] or 0) * t
    end
    return result
end

local function levelUpWeights(model)
    local level = model.levelUpMeter or 10
    if level <= 10 then
        return {
            levelUpFit = 0.30,
            beginnerSafety = 0.25,
            popularity = 0.15,
            communityFavorite = 0.10,
            communityScoreability = 0.08,
            machineRecentActivity = 0.05,
            exploration = 0.07,
        }
    elseif level <= 12 then
        return {
            levelUpFit = 0.25,
            tech = 0.20,
            stamina = 0.12,
            localPeerPerformance = 0.10,
            localScoringEase = 0.10,
            popularity = 0.08,
            communityFavorite = 0.05,
            exploration = 0.10,
        }
    elseif level <= 14 then
        return {
            levelUpFit = 0.22,
            stamina = 0.23,
            tech = 0.15,
            localPeerPerformance = 0.12,
            localScoringEase = 0.10,
            popularity = 0.05,
            communityFavorite = 0.03,
            exploration = 0.10,
        }
    else
        return {
            levelUpFit = 0.20,
            stamina = 0.35,
            tech = 0.08,
            localPeerPerformance = 0.12,
            localScoringEase = 0.10,
            popularity = 0.03,
            communityFavorite = 0.02,
            exploration = 0.10,
        }
    end
end

local function techHistoryMeterFit(model, feature, meter)
    local stat =
        model.techMastery
        and model.techMastery[feature]

    if not stat
        or not stat.meterWeights
        or (stat.meterWeightTotal or 0) <= 0
    then
        return 0.5
    end

    local sigma =
        tonumber(
            (curriculum().RecentInterest or {}).meterPreferenceSigma
        ) or 1.25

    sigma = math.max(0.50, sigma)

    local numerator = 0
    local denominator = 0

    for historicalMeter, weight in pairs(stat.meterWeights) do
        if weight > 0 then
            numerator =
                numerator +
                gaussian(
                    meter - historicalMeter,
                    sigma
                ) * weight
            denominator = denominator + weight
        end
    end

    if denominator <= 0 then return 0.5 end

    -- Normalize to this player's own strongest tech-specific meter.
    local best = 0
    for candidateMeter = 1, (curriculum().JokeMeterMax or 30) do
        local score = 0
        for historicalMeter, weight in pairs(stat.meterWeights) do
            score =
                score +
                gaussian(
                    candidateMeter - historicalMeter,
                    sigma
                ) * weight
        end
        best = math.max(best, score / denominator)
    end

    if best <= 0 then return 0.5 end
    return clamp((numerator / denominator) / best, 0, 1)
end

local function curriculumBandConfig(level)
    local bands = curriculum().Bands or {}

    for _, band in ipairs(bands) do
        if level >= (band.minLevel or 1)
            and level <= (band.maxLevel or 999)
        then
            return band
        end
    end

    return {
        techLevelSigma = 1.75,
        interestTechLevelSigma = 2.00,

        weights = {
            techIntensity = 0.50,
            techLevelFit = 0.18,
            metadata = 0.05,
            stamina = 0.07,
            localPeerPerformance = 0.05,
            localScoringEase = 0.03,
            exploration = 0.05,
            popularity = 0.04,
            personalAffinity = 0.03,
        },
    }
end

local function curriculumBandWeights(level, isInterest)
    local band =
        curriculumBandConfig(level)

    if isInterest
        and band.interestWeights
    then
        return band.interestWeights
    end

    return band.weights or {}
end

local function curriculumRuleAllowed(model, rule)
    if not rule then return false end
    local stat = model.techMastery[rule.tech]
    if rule.hideWhenMastered and stat and stat.mastered then return false end
    for _, required in ipairs(rule.requiresMastery or {}) do
        if not (model.techMastery[required] and model.techMastery[required].mastered) then
            return false
        end
    end
    return true
end

local function buildDynamicModes(model)
    model.dynamicModes = {}
    local order = {"ForYou"}
    local level = model.skillFocusLevel

    if model.levelUpMeter then order[#order + 1] = "LevelUp" end

    local alreadyTech = {}
    if level then
        local levelRule = (curriculum().Levels or {})[level]
        if levelRule then
            for _, rule in ipairs(levelRule.automatic or {}) do
                if curriculumRuleAllowed(model, rule) then
                    local spec = curriculum().Tech[rule.tech]
                    if spec then
                        local key = "Curriculum_" .. rule.tech
                        model.dynamicModes[key] = {
                            section = spec.label or (rule.tech .. " Recs"),
                            techFeature = rule.tech,

                            techTargetMeter = level,
                            techLevelSigma =
                                tonumber(
                                    curriculumBandConfig(level).techLevelSigma
                                )
                                or 1.25,

                            weights =
                                curriculumBandWeights(
                                    level,
                                    false
                                ),

                            requireTechFit =
                                tonumber(spec.minCandidateFit)
                                or 0.40,

                            requireTechIntensity =
                                tonumber(spec.minCandidateIntensity)
                                or 0.25,

                            maxResults =
                                tonumber(spec.automaticMaxResults)
                                or 25,

                            difficultyGateFloor = 0.25,
                        }
                        order[#order + 1] = key
                        alreadyTech[rule.tech] = true
                    end
                end
            end
        end
    end

    -- Interest-driven sections can appear starting at level 9 even when that
    -- technique is no longer part of the automatic curriculum.
    local interestCfg = curriculum().RecentInterest or {}
    if level and level >= (interestCfg.minLevel or 9) then
        local interests = {}
        for feature, stat in pairs(model.techMastery) do
            local spec = curriculum().Tech[feature]
            local interestAllowed = spec and not alreadyTech[feature]
                and level >= (tonumber(spec.interestMinLevel) or (interestCfg.minLevel or 9))
                and level <= (tonumber(spec.interestMaxLevel) or 999)
                and stat.recentCharts >= (interestCfg.minCharts or 2)
                and stat.recentInterest >= (interestCfg.minNormalizedInterest or 0.35)

            if interestAllowed then
                for _, required in ipairs(spec.interestRequiresMastery or {}) do
                    if not (model.techMastery[required] and model.techMastery[required].mastered) then
                        interestAllowed = false
                        break
                    end
                end
            end

            if interestAllowed then
                interests[#interests + 1] = {feature = feature, value = stat.recentInterest}
            end
        end
        table.sort(interests, function(a,b) return a.value > b.value end)
        for i = 1, math.min(#interests, interestCfg.maxSections or 2) do
            local feature = interests[i].feature
            local spec = curriculum().Tech[feature]
            local key = "Interest_" .. feature
            model.dynamicModes[key] = {
                section =
                    (
                        spec.interestLabel
                        or spec.label
                        or (feature .. " Recs")
                    ),

                techFeature = feature,
                isInterestTech = true,

                techTargetMeter =
                    model.levelUpMeter
                    or model.skillFocusLevel
                    or level,

                -- "More X" can go down into the player's normal play range,
                -- but never above the current progression ceiling.
                techCeilingMeter =
                    model.levelUpMeter
                    or model.reliableMeter
                    or model.skillFocusLevel
                    or level,

                techCeilingQuota =
                    tonumber(
                        (curriculum().RecentInterest or {}).ceilingQuota
                    ) or 0.25,

                techCeilingBand =
                    tonumber(
                        (curriculum().RecentInterest or {}).ceilingBand
                    ) or 1,

                techLevelSigma =
                    tonumber(
                        curriculumBandConfig(
                            level
                        ).interestTechLevelSigma
                    )
                    or tonumber(
                        curriculumBandConfig(
                            level
                        ).techLevelSigma
                    )
                    or 2.0,

                weights =
                    curriculumBandWeights(
                        level,
                        true
                    ),

                requireTechFit =
                    tonumber(spec.minCandidateFit)
                    or 0.40,

                requireTechIntensity =
                    tonumber(spec.minCandidateIntensity)
                    or 0.25,

                maxResults =
                    tonumber(spec.interestMaxResults)
                    or 18,

                difficultyGateFloor = 0.20,
            }
            order[#order + 1] = key
        end
    end

    local rhythmCfg =
        curriculum().Rhythms or {}

    local rhythmNormallyAllowed =
        level
        and level >=
            (
                tonumber(
                    rhythmCfg.interestMinLevel
                )
                or 9
            )

    local rhythmEarlyAllowed =
        level
        and level <
            (
                tonumber(
                    rhythmCfg.interestMinLevel
                )
                or 9
            )
        and model.rhythmFamiliarity >=
            (
                tonumber(
                    rhythmCfg.earlyInterestFamiliarity
                )
                or 0.65
            )

    if (rhythmNormallyAllowed or rhythmEarlyAllowed)
        and model.recentRhythmCharts >=
            (
                tonumber(
                    rhythmCfg.interestMinCharts
                )
                or 2
            )
        and model.recentRhythmInterest >=
            (
                tonumber(
                    rhythmCfg.interestMin
                )
                or 0.34
            )
    then
        local key = "Interest_rhythms"

        model.dynamicModes[key] = {
            section =
                rhythmCfg.section
                or "More Rhythms",

            rhythmMode = true,

            requireRhythm =
                tonumber(
                    rhythmCfg.candidateMin
                )
                or 0.42,

            maxResults =
                tonumber(
                    rhythmCfg.maxResults
                )
                or 16,

            weights = {
                rhythmFeature = 0.42,
                difficulty = 0.14,
                stamina = 0.10,
                metadata = 0.08,
                personalAffinity = 0.05,
                localPeerPerformance = 0.05,
                localScoringEase = 0.04,
                popularity = 0.04,
                communityFavorite = 0.03,
                exploration = 0.05,
            },

            difficultyGateFloor = 0.30,
        }

        order[#order + 1] = key
    end

    local quirkCfg = curriculum().Quirkiness or {}
    local quirkAutomatic = level and level == (tonumber(quirkCfg.automaticLevel) or 10)
    if quirkAutomatic then
        local key = "Curriculum_quirky"
        model.dynamicModes[key] = {
            section = quirkCfg.section or "Quirky Recs",
            quirkMode = true,
            requireQuirkiness = tonumber(quirkCfg.candidateMin) or 0.42,
            maxResults = tonumber(quirkCfg.maxResults) or 20,
            weights = {
                quirkFeature = 0.38,
                difficulty = 0.15,
                popularity = 0.15,
                machineRecentActivity = 0.08,
                communityFavorite = 0.08,
                communityScoreability = 0.06,
                metadata = 0.04,
                exploration = 0.06,
            },
            difficultyGateFloor = 0.35,
        }
        order[#order + 1] = key
    elseif level and level >= (tonumber(quirkCfg.interestMinLevel) or 10)
        and model.recentQuirkCharts >= (tonumber(quirkCfg.interestMinCharts) or 2)
        and model.recentQuirkInterest >= (tonumber(quirkCfg.interestMin) or 0.32)
    then
        local key = "Interest_quirky"
        model.dynamicModes[key] = {
            section = quirkCfg.interestSection or "More Quirky Charts",
            quirkMode = true,
            requireQuirkiness = tonumber(quirkCfg.candidateMin) or 0.42,
            maxResults = tonumber(quirkCfg.interestMaxResults) or 16,
            weights = {
                quirkFeature = 0.32,
                quirkAffinity = 0.16,
                metadata = 0.14,
                tech = 0.08,
                stamina = 0.08,
                localPeerPerformance = 0.05,
                popularity = 0.05,
                exploration = 0.12,
            },
            difficultyGateFloor = 0.30,
        }
        order[#order + 1] = key
    end

    if model.scoreWellReady then order[#order + 1] = "ScoreWell" end
    order[#order + 1] = "YouMightLike"
    order[#order + 1] = "PopularPicks"
    model.modeOrder = order
end

local function getModeConfig(model, modeKey)
    return (model.dynamicModes and model.dynamicModes[modeKey])
        or SLRecommendations.Modes[modeKey]
        or SLRecommendations.Modes.ForYou
end

local function getModeSection(model, modeKey)
    if modeKey == "LevelUp" and model.levelUpMeter then
        return "Level Up to " .. tostring(model.levelUpMeter)
    end
    return getModeConfig(model, modeKey).section
end

local function getModeWeights(model, modeKey)
    local mode = getModeConfig(model, modeKey)
    if modeKey == "ForYou" then
        return blendWeights(COLD_FOR_YOU_WEIGHTS, SLRecommendations.Config.Weights, model.personalConfidence or 0)
    elseif modeKey == "YouMightLike" then
        return blendWeights(COLD_LIKE_WEIGHTS, mode.weights, model.personalConfidence or 0)
    elseif modeKey == "LevelUp" then
        return levelUpWeights(model)
    end
    return mode.weights or {}
end

local function buildModel(pn, stepsType)
    local profile = getPlayerProfile(pn)
    local isGuest = profileIsGuest(profile)
    local usePersonalData = profile ~= nil and not isGuest

    local chartGroups, groupStats = collectChartGroups(
        pn,
        stepsType,
        usePersonalData and profile or nil
    )

    local model = {
        pn = pn,
        profile = profile,
        profileIsGuest = isGuest,
        usePersonalData = usePersonalData,
        stepsType = stepsType,

        playerMaturity = isGuest and "guest" or "cold",
        personalConfidence = 0,
        passedHistoryCharts = 0,
        skillByMeter = {},
        workingMeter = nil,
        reliableMeter = nil,
        masteredMeter = nil,
        skillComfortMeter = nil,
        skillFocusLevel = nil,
        levelUpMeter = nil,
        scoreWellReady = false,
        techMastery = {},
        dynamicModes = {},

        communityFavoriteCounts = {},
        communityFavoriteMax = 0,
        communityFavoriteProfiles = 0,
        targetMeter = nil,
        meterQ25 = nil,
        meterQ75 = nil,
        difficultySigma = SLRecommendations.Config.DifficultyMinSigma,
        targetTech = {},
        targetStamina = {},
        targetQuirkiness = 0,
        totalQuirkWeight = 0,
        recentQuirkWeight = 0,
        recentQuirkDenominator = 0,
        recentQuirkCharts = 0,
        recentQuirkInterest = 0,

        recentRhythmWeight = 0,
        recentRhythmDenominator = 0,
        recentRhythmCharts = 0,
        recentRhythmInterest = 0,
        rhythmPassedCharts = 0,
        rhythmPassedScores = {},
        rhythmPassedMedian = nil,
        rhythmFamiliarity = 0,

        chartShapeCache = {},
        chartQuirkCache = {},
        artistAffinity = {},
        genreAffinity = {},
        creditAffinity = {},
        totalHistoryWeight = 0,
        maxPlayerChartPlays = 0,
        maxMachineChartPlays = 0,
        playedHistoryCharts = 0,
        favoriteSongs = 0,

        -- Local peer-relative scoring model.  v10 records this signal for
        -- validation but does not let it alter ranking yet.
        localPeerDirectory = nil,
        localPeerByGroupKey = {},
        localPeerExamples = {},
        localPeerObservedIdentities = {},
        localPeerBenchmarkCharts = 0,
        localPeerAveragePercentile = nil,
        localPeerAverageRelative = nil,
        localPeerGuidOpponentObservations = 0,
        localPeerNameOnlyOpponentObservations = 0,
        localPeerExcludedNonPassScores = 0,
        localPeerFailedOnlyCharts = 0,
        localPeerRegression = nil,

        localScoringDifficulty = nil,
        localScoringDifficultyRegression = nil,

        modelBuildSeconds = 0,
        candidateScoringSeconds = 0,
        modeRankingSeconds = 0,
        rankingSeconds = 0,
        totalGenerationSeconds = 0,

        -- Dedupe diagnostics.
        totalChartEntries = groupStats.totalEntries or 0,
        uniqueChartIdentities = groupStats.uniqueIdentities or 0,
        duplicateHashGroups = groupStats.duplicateHashGroups or 0,
        duplicateChartCopiesCollapsed = groupStats.duplicateChartCopiesCollapsed or 0,

        -- Internal cache used by Generate().  Keeping grouping and ranking on
        -- the same identities prevents duplicate installs from influencing the
        -- learned model and then merely being hidden at presentation time.
        _chartGroups = chartGroups,
    }

    for i = 1, #TECH_CATEGORIES do
        model.targetTech[i] = 0
    end

    local meterSamples = {}
    local peerPercentileTotal = 0
    local peerRelativeTotal = 0
    local peerWeightTotal = 0

    model.communityFavoriteCounts,
    model.communityFavoriteMax,
    model.communityFavoriteProfiles = buildCommunityFavorites()

    model.localPeerDirectory =
        buildPeerDirectory(usePersonalData and profile or nil)

    -- Favorites remain song-level metadata evidence.
    for song in ivalues(SONGMAN:GetAllSongs()) do
        if usePersonalData and isFavorited(pn, song) then
            model.favoriteSongs = model.favoriteSongs + 1
            addWeighted(
                model.artistAffinity,
                song:GetDisplayArtist(),
                SLRecommendations.Config.FavoriteSongMetadataBoost
            )
            addWeighted(
                model.genreAffinity,
                song:GetGenre(),
                SLRecommendations.Config.FavoriteSongMetadataBoost
            )
        end
    end

    -- Chart-specific learning is performed once per unique chart identity.
    for _, group in ipairs(chartGroups) do
        local rep = group.representative
        if rep then
            local playerPlays = rep.playerPlays
            local machinePlays = rep.machinePlays

            model.maxPlayerChartPlays =
                math.max(model.maxPlayerChartPlays, playerPlays)
            model.maxMachineChartPlays =
                math.max(model.maxMachineChartPlays, machinePlays)

            if usePersonalData and playerPlays > 0 then
                local historyWeight = log1p(playerPlays)
                if group.favorite then
                    historyWeight =
                        historyWeight + SLRecommendations.Config.FavoritePlayedChartBoost
                end

                if historyWeight > 0 then
                    model.playedHistoryCharts = model.playedHistoryCharts + 1
                    model.totalHistoryWeight =
                        model.totalHistoryWeight + historyWeight

                    local historyMeter = rep.steps:GetMeter()
                    if historyMeter >= 1 and historyMeter <= (curriculum().JokeMeterMax or 30) then
                        meterSamples[#meterSamples + 1] = {
                            value = historyMeter,
                            weight = historyWeight,
                        }
                    end

                    addWeighted(
                        model.artistAffinity,
                        rep.song:GetDisplayArtist(),
                        historyWeight
                    )
                    addWeighted(
                        model.genreAffinity,
                        rep.song:GetGenre(),
                        historyWeight
                    )
                    addWeighted(
                        model.creditAffinity,
                        rep.steps:GetAuthorCredit(),
                        historyWeight,
                        normalizeCredit
                    )

                    local tech =
                        getTechVector(
                            rep.steps,
                            pn,
                            rep.song
                        )

                    for i = 1, #tech do
                        model.targetTech[i] =
                            model.targetTech[i] +
                            tech[i] * historyWeight
                    end

                    local shape =
                        getChartShapeFeatures(
                            model,
                            rep.steps,
                            rep.song,
                            group
                        )

                    addWeightedShape(
                        model.targetStamina,
                        shape,
                        historyWeight
                    )
                end

                local passedDP = select(1, getGroupBestPassedPercentDP(profile, group))
                if passedDP then
                    model.passedHistoryCharts = model.passedHistoryCharts + 1
                    local meter = rep.steps:GetMeter()
                    local jokeMax = curriculum().JokeMeterMax or 30
                    if meter >= 1 and meter <= jokeMax then
                        local skillCfg = curriculum().Skill or DEFAULT_CURRICULUM.Skill
                        local meterStat = ensureSkillMeterStat(model, meter)
                        meterStat.count = meterStat.count + 1
                        meterStat.scores[#meterStat.scores + 1] = passedDP
                        if passedDP >= (skillCfg.decentDP or 0.80) then meterStat.decent = meterStat.decent + 1 end
                        if passedDP >= (skillCfg.strongDP or 0.90) then meterStat.strong = meterStat.strong + 1 end
                    end
                end

                -- Recent technique interest is based on what the player has
                -- actually been playing, even if they have not passed it yet.
                -- Mastery, however, remains pass-only.
                local tech, rawTech = getTechVector(rep.steps, pn, rep.song)
                local notation = parseChartNotation(rep.steps)
                local quirk = getChartQuirkiness(model, rep.steps, rep.song, group, notation)
                local days = getDaysSinceLastPlayed(profile, rep.song, rep.steps)
                local recencyLookback = math.max(1, (curriculum().RecentInterest or {}).lookbackDays or 120)
                local recencyWeight = days and math.exp(-days / recencyLookback) or 0

                model.targetQuirkiness = model.targetQuirkiness + quirk.score * historyWeight
                model.totalQuirkWeight = model.totalQuirkWeight + historyWeight

                local quirkCfg = curriculum().Quirkiness or {}
                local quirkLookback = math.max(1, tonumber(quirkCfg.interestLookbackDays) or recencyLookback)
                local quirkRecencyWeight = days and math.exp(-days / quirkLookback) or 0
                if quirkRecencyWeight > 0 and quirk.score >= (tonumber(quirkCfg.candidateMin) or 0.42) then
                    local interestWeight = quirkRecencyWeight * log1p(playerPlays)
                    model.recentQuirkWeight = model.recentQuirkWeight + interestWeight * quirk.score
                    model.recentQuirkDenominator = model.recentQuirkDenominator + interestWeight
                    model.recentQuirkCharts = model.recentQuirkCharts + 1
                end

                local shape =
                    getChartShapeFeatures(
                        model,
                        rep.steps,
                        rep.song,
                        group
                    )

                local rhythm =
                    getRhythmEvidence(
                        shape,
                        notation
                    )

                local rhythmCfg =
                    curriculum().Rhythms or {}

                local rhythmMin =
                    tonumber(rhythmCfg.candidateMin)
                    or 0.42

                local rhythmLookback =
                    math.max(
                        1,
                        tonumber(
                            rhythmCfg.interestLookbackDays
                        ) or recencyLookback
                    )

                local rhythmRecencyWeight =
                    days
                    and math.exp(
                        -days / rhythmLookback
                    )
                    or 0

                if rhythm.evidence >= rhythmMin then
                    if rhythmRecencyWeight > 0 then
                        local interestWeight =
                            rhythmRecencyWeight *
                            log1p(playerPlays)

                        model.recentRhythmWeight =
                            model.recentRhythmWeight +
                            interestWeight *
                            rhythm.evidence

                        model.recentRhythmDenominator =
                            model.recentRhythmDenominator +
                            interestWeight

                        model.recentRhythmCharts =
                            model.recentRhythmCharts + 1
                    end

                    if passedDP
                        and passedDP >=
                            (
                                tonumber(
                                    rhythmCfg.goodScoreDP
                                )
                                or 0.80
                            )
                    then
                        model.rhythmPassedCharts =
                            model.rhythmPassedCharts + 1

                        model.rhythmPassedScores[
                            #model.rhythmPassedScores + 1
                        ] = passedDP
                    end
                end

                for feature, spec in pairs(curriculum().Tech or {}) do
                    local evidence = techFeatureEvidence(tech, rawTech, notation, feature)
                    local stat = ensureTechStat(model, feature)
                    local interestMin = tonumber(spec.interestMinEvidence) or 0.35

                    -- Learn where this player actually chooses to play this
                    -- technique.  Use meaningful historical plays, not only
                    -- recent plays and not only passes.
                    if evidence.fit >= interestMin then
                        local meter = rep.steps:GetMeter()
                        local jokeMax = curriculum().JokeMeterMax or 30

                        if meter >= 1 and meter <= jokeMax then
                            local evidenceWeight =
                                math.max(
                                    evidence.intensity or 0,
                                    (evidence.fit or 0) * 0.50
                                )

                            local meterWeight =
                                log1p(playerPlays) * evidenceWeight

                            if meterWeight > 0 then
                                stat.meterWeights[meter] =
                                    (stat.meterWeights[meter] or 0)
                                    + meterWeight
                                stat.meterWeightTotal =
                                    stat.meterWeightTotal
                                    + meterWeight
                            end
                        end
                    end

                    if evidence.masteryEligible then
                        if passedDP and passedDP >= (tonumber(spec.trainingMinDP) or 0.75) then
                            stat.qualifying = stat.qualifying + 1
                            stat.scores[#stat.scores + 1] = passedDP
                            if passedDP >= (tonumber(spec.strongDP) or 0.90) then
                                stat.strong = stat.strong + 1
                            end
                        end
                    end

                    if evidence.fit >= interestMin and recencyWeight > 0 then
                        stat.recentWeight = stat.recentWeight
                            + recencyWeight * log1p(playerPlays) * evidence.fit
                        stat.recentCharts = stat.recentCharts + 1
                    end
                end

                if SLRecommendations.Config.LocalPeerEnabled then
                    local peerStat =
                        calculatePeerStat(model, group)

                    if peerStat then
                        model.localPeerByGroupKey[group.key] =
                            peerStat

                        model.localPeerGuidOpponentObservations =
                            model.localPeerGuidOpponentObservations +
                            peerStat.guidOpponents

                        model.localPeerNameOnlyOpponentObservations =
                            model.localPeerNameOnlyOpponentObservations +
                            peerStat.nameOnlyOpponents

                        if peerStat.opponents >=
                            SLRecommendations.Config.LocalPeerMinOpponents
                        then
                            model.localPeerBenchmarkCharts =
                                model.localPeerBenchmarkCharts + 1

                            local example = {
                                key = group.key,
                                song = rep.song,
                                steps = rep.steps,
                                title =
                                    rep.song:GetDisplayFullTitle(),
                                meter = rep.steps:GetMeter(),
                                shape =
                                    getChartShapeFeatures(
                                        model,
                                        rep.steps,
                                        rep.song,
                                        group
                                    ),
                                tech =
                                    getTechVector(
                                        rep.steps,
                                        pn,
                                        rep.song
                                    ),
                                relative = peerStat.relative,
                                percentile = peerStat.percentile,
                                gap = peerStat.gap,
                                confidence = peerStat.confidence,
                                opponents = peerStat.opponents,
                            }

                            model.localPeerExamples[
                                #model.localPeerExamples + 1
                            ] = example

                            peerPercentileTotal =
                                peerPercentileTotal +
                                peerStat.percentile *
                                peerStat.confidence

                            peerRelativeTotal =
                                peerRelativeTotal +
                                peerStat.relative *
                                peerStat.confidence

                            peerWeightTotal =
                                peerWeightTotal +
                                peerStat.confidence
                        end
                    end
                end
            end
        end
    end

    if #meterSamples > 0 then
        model.targetMeter = weightedQuantile(meterSamples, 0.50)
        model.meterQ25 = weightedQuantile(meterSamples, 0.25)
        model.meterQ75 = weightedQuantile(meterSamples, 0.75)

        local iqr = math.max(
            0,
            (model.meterQ75 or model.targetMeter) -
            (model.meterQ25 or model.targetMeter)
        )
        local estimatedSigma =
            iqr > 0
            and (iqr / 1.349)
            or SLRecommendations.Config.DifficultyMinSigma

        model.difficultySigma = clamp(
            estimatedSigma,
            SLRecommendations.Config.DifficultyMinSigma,
            SLRecommendations.Config.DifficultyMaxSigma
        )
    end

    if model.totalHistoryWeight > 0 then
        for i = 1, #model.targetTech do
            model.targetTech[i] =
                model.targetTech[i] /
                model.totalHistoryWeight
        end

        divideShape(
            model.targetStamina,
            model.totalHistoryWeight
        )
    end

    if model.totalQuirkWeight > 0 then
        model.targetQuirkiness = model.targetQuirkiness / model.totalQuirkWeight
    end
    if model.recentQuirkDenominator > 0 then
        model.recentQuirkInterest = clamp(
            model.recentQuirkWeight / model.recentQuirkDenominator,
            0,
            1
        )
    end

    if model.recentRhythmDenominator > 0 then
        model.recentRhythmInterest =
            clamp(
                model.recentRhythmWeight /
                model.recentRhythmDenominator,
                0,
                1
            )
    end

    if #model.rhythmPassedScores > 0 then
        model.rhythmPassedMedian =
            median(
                model.rhythmPassedScores
            )
    end

    do
        local rhythmCfg =
            curriculum().Rhythms or {}

        local passConfidence =
            clamp(
                model.rhythmPassedCharts /
                math.max(
                    1,
                    tonumber(
                        rhythmCfg.familiarityPassedCharts
                    ) or 3
                ),
                0,
                1
            )

        local scoreConfidence = 0

        if model.rhythmPassedMedian then
            local goodDP =
                tonumber(rhythmCfg.goodScoreDP)
                or 0.80

            scoreConfidence =
                clamp(
                    (
                        model.rhythmPassedMedian -
                        (goodDP - 0.10)
                    ) /
                    0.20,
                    0,
                    1
                )
        end

        local recentConfidence =
            clamp(
                model.recentRhythmCharts /
                math.max(
                    1,
                    tonumber(
                        rhythmCfg.familiarityRecentCharts
                    ) or 4
                ),
                0,
                1
            ) *
            model.recentRhythmInterest

        model.rhythmFamiliarity =
            clamp(
                math.max(
                    passConfidence *
                    math.max(
                        0.50,
                        scoreConfidence
                    ),
                    recentConfidence
                ),
                0,
                1
            )
    end

    if peerWeightTotal > 0 then
        model.localPeerAveragePercentile =
            peerPercentileTotal / peerWeightTotal
        model.localPeerAverageRelative =
            peerRelativeTotal / peerWeightTotal
    end

    finalizeSkillAndTechProfile(model)

    model.localPeerRegression =
        fitLocalPeerRegression(model)

    model.localScoringDifficulty =
        fitLocalScoringDifficulty(model)

    model.localScoringDifficultyRegression =
        fitLocalScoringDifficultyRegression(model)

    normalizeMap(model.artistAffinity)
    normalizeMap(model.genreAffinity)
    normalizeMap(model.creditAffinity)

    buildDynamicModes(model)

    return model
end

local function weightedTotalWithWeights(components, weights)
    local numerator = 0
    local denominator = 0

    -- Keep a fixed denominator.  Missing evidence must not make the remaining
    -- evidence artificially stronger.
    for name, weight in pairs(weights or {}) do
        if weight and weight > 0 then
            denominator = denominator + weight
            numerator =
                numerator +
                (components[name] or 0) * weight
        end
    end

    if denominator <= 0 then return 0 end
    return numerator / denominator
end

local function weightedTotal(components)
    return weightedTotalWithWeights(
        components,
        SLRecommendations.Config.Weights
    )
end

local function recommendationReasons(candidate, weights)
    local labels = {
        difficulty = "difficulty fit",
        tech = "similar tech profile",
        stamina = "stamina/density fit",
        metadata = "artist/genre/stepartist affinity",
        personalAffinity = "you replay this chart",
        personalFreshness = "personal rediscovery",
        machineFreshness = "cabinet rediscovery",
        machineRecentActivity = "recently played on this machine",
        popularity = "machine popularity",
        communityFavorite = "liked by local players",
        communityScoreability = "scores well on this machine",
        beginnerSafety = "beginner-friendly patterning",
        quirkAffinity = "similar gimmick/quirk profile",
        quirkSafety = "low-gimmick chart",
        quirkFeature = "gimmick/mod chart fit",
        rhythmFeature = "rhythm/skittles fit",
        rhythmEvidence = "rhythm-heavy chart",
        rhythmIntensity = "strong rhythm emphasis",
        rhythmSafety = "beginner-friendly rhythm complexity",
        levelUpFit = "next-level difficulty",
        techFeature = "targeted technique presence",
        techIntensity = "strong targeted-tech emphasis",
        techLevelFit = "appropriate tech-training level",
        techHistoryLevelFit = "matches your usual level for this technique",
        priorPositive = "favorite/strong prior score",
        exploration = candidate.playerPlays <= 0
            and "new-to-you exploration"
            or "less-played chart",
        localPeerPerformance = "you tend to score well on charts like this",
        localScoringExpected = "locally favorable expected score",
        localScoringEase = "locally easier to score",
    }

    weights = weights or SLRecommendations.Config.Weights

    local ranked = {}
    for name, value in pairs(candidate.components) do
        local weight = weights[name] or 0
        ranked[#ranked + 1] = {
            name = name,
            value = value,
            contribution = value * weight,
        }
    end

    table.sort(ranked, function(a, b)
        if a.contribution == b.contribution then
            return a.value > b.value
        end
        return a.contribution > b.contribution
    end)

    local reasons = {}
    for _, item in ipairs(ranked) do
        if #reasons >= 3 then break end
        if item.value >= 0.55 and item.contribution >= 0.025 then
            reasons[#reasons + 1] = labels[item.name] or item.name
        end
    end

    return reasons
end

local function scoreCandidate(model, entry, group)
    local song = entry.song
    local steps = entry.steps
    local profile = model.profile
    local machine = PROFILEMAN:GetMachineProfile()

    local playerPlays = entry.playerPlays
    local machinePlays = entry.machinePlays
    local favorite = (group and group.favorite) or entry.favorite
    local bestDP = getBestPercentDP(profile, song, steps)

    local components = {
        difficulty = 0,
        tech = 0,
        stamina = 0,
        metadata = 0,
        personalAffinity = 0,
        personalFreshness = 0,
        machineFreshness = 0,
        machineRecentActivity = 0,
        popularity = 0,
        communityFavorite = 0,
        communityScoreability = 0,
        beginnerSafety = 1,
        quirkiness = 0,
        quirkAffinity = 0,
        quirkSafety = 1,

        rhythmEvidence = 0,
        rhythmIntensity = 0,
        rhythmSafety = 1,

        levelUpFit = 0,
        priorPositive = 0,
        exploration = 0,

        -- Local peer performance is used by Score Well.
        localPeerPerformance = 0,

        -- Literal expected score remains diagnostic only.
        localScoringExpected = 0,

        -- Robust confidence-shrunk scoring ease.  Score Well uses this.
        localScoringEase = 0,
    }

    local difficultyFit = nil
    if model.targetMeter then
        difficultyFit =
            gaussian(steps:GetMeter() - model.targetMeter, model.difficultySigma)
        components.difficulty = difficultyFit
    end

    local chartShape =
        getChartShapeFeatures(
            model,
            steps,
            song,
            group
        )

    local candidateTech, candidateTechRaw =
        getTechVector(
            steps,
            model.pn,
            song
        )

    local notation = parseChartNotation(steps)
    local quirk = getChartQuirkiness(model, steps, song, group, notation)

    local rhythm =
        getRhythmEvidence(
            chartShape,
            notation
        )

    components.quirkiness = quirk.score
    components.quirkSafety = 1 - quirk.score
    if model.totalQuirkWeight > 0 then
        components.quirkAffinity = clamp(
            1 - math.abs(quirk.score - model.targetQuirkiness),
            0,
            1
        )
    end

    components.rhythmEvidence =
        rhythm.evidence

    components.rhythmIntensity =
        rhythm.intensity

    local rhythmPassedDP = nil

    if model.usePersonalData
        and profile
    then
        rhythmPassedDP =
            select(
                1,
                getGroupBestPassedPercentDP(
                    profile,
                    group
                )
            )
    end

    components.rhythmSafety =
        rhythmBeginnerSafety(
            model,
            rhythm,
            playerPlays,
            rhythmPassedDP
        )

    components.beginnerSafety =
        beginnerSafetyForTech(
            model,
            candidateTech
        )

    local skillLevel = model.skillFocusLevel or model.skillComfortMeter or 0
    if model.playerMaturity ~= "established" and skillLevel <= 10 then
        -- Super-quirky charts should not leak into beginner general-purpose
        -- recommendations.  The dedicated Quirky Recs mode bypasses this by
        -- targeting quirkiness directly instead of beginnerSafety.
        components.beginnerSafety =
            components.beginnerSafety *
            math.max(
                0.05,
                math.pow(
                    components.quirkSafety,
                    0.85
                )
            )

        if skillLevel < 9 then
            components.beginnerSafety =
                components.beginnerSafety *
                components.rhythmSafety
        end
    end

    if model.totalHistoryWeight > 0 then
        components.tech =
            techSimilarity(
                model.targetTech,
                candidateTech
            ) or 0

        components.stamina =
            staminaSimilarity(
                model.targetStamina,
                chartShape
            ) or 0
    end

    components.metadata =
        scoreMetadata(model, song, steps)

    if model.maxPlayerChartPlays > 0 and playerPlays > 0 then
        components.personalAffinity = clamp(
            log1p(playerPlays) / log1p(model.maxPlayerChartPlays),
            0,
            1
        )
    end

    local personalDays = getDaysSinceLastPlayed(profile, song, steps)
    if playerPlays > 0 and personalDays then
        components.personalFreshness = clamp(
            personalDays / SLRecommendations.Config.PersonalStaleDays,
            0,
            1
        )
    end

    local machineDays = getDaysSinceLastPlayed(machine, song, steps)
    if machinePlays > 0 and machineDays then
        components.machineFreshness = clamp(
            machineDays / SLRecommendations.Config.MachineStaleDays,
            0,
            1
        )
        components.machineRecentActivity = math.exp(
            -machineDays / SLRecommendations.Config.MachineRecentActivityDays
        )
    end

    if model.maxMachineChartPlays > 0 and machinePlays > 0 then
        components.popularity = clamp(
            log1p(machinePlays) / log1p(model.maxMachineChartPlays),
            0,
            1
        )
    end

    local communityKey = songCommunityKey(song)
    if communityKey and model.communityFavoriteMax > 0 then
        components.communityFavorite = clamp(
            (model.communityFavoriteCounts[communityKey] or 0) / model.communityFavoriteMax,
            0, 1
        )
    end

    components.communityScoreability = getMachineScoreability(machine, entry)

    if model.levelUpMeter then
        components.levelUpFit = gaussian(
            steps:GetMeter() - model.levelUpMeter,
            SLRecommendations.Config.LevelUpSigma
        )
    end

    if favorite then
        components.priorPositive = 1
    end
    if bestDP then
        components.priorPositive = math.max(
            components.priorPositive,
            clamp((bestDP - 0.90) / 0.10, 0, 1)
        )
    end

    if playerPlays <= 0 then
        components.exploration = 1
    elseif model.maxPlayerChartPlays > 0 then
        components.exploration = clamp(
            1 - (log1p(playerPlays) / log1p(model.maxPlayerChartPlays)),
            0,
            1
        )
    end

    local localPeer =
        predictLocalPeerPerformance(
            model,
            song,
            steps,
            group
        )

    if localPeer then
        components.localPeerPerformance =
            localPeer.fit
    end

    local localScoring =
        predictLocalScoringForChart(
            model,
            song,
            steps,
            group
        )

    if localScoring then
        components.localScoringExpected =
            localScoring.shrunkExpectedDp

        components.localScoringEase =
            localScoring.ease
    end

    local rawScore = weightedTotal(components)

    local difficultyGate = 1
    if difficultyFit ~= nil then
        difficultyGate =
            SLRecommendations.Config.DifficultyGateFloor +
            (1 - SLRecommendations.Config.DifficultyGateFloor) * difficultyFit
    end

    local hash, hashVersion = getGrooveStatsIdentity(steps)

    local candidate = {
        song = song,
        steps = steps,
        score = rawScore * difficultyGate,
        rawScore = rawScore,
        difficultyGate = difficultyGate,
        components = components,
        playerPlays = playerPlays,
        machinePlays = machinePlays,
        favorite = favorite,
        bestPercentDP = bestDP,
        personalDaysSince = personalDays,
        machineDaysSince = machineDays,
        meter = steps:GetMeter(),
        artist = song:GetDisplayArtist(),
        genre = song:GetGenre(),
        credit = steps:GetAuthorCredit(),
        peakNps = chartShape.peakNps,
        chartShape = chartShape,
        techVector = candidateTech,
        techRawCounts = candidateTechRaw,
        chartNotation = notation,
        quirkiness = quirk,
        rhythm = rhythm,
        techFeatureFits = {},
        techFeatureIntensity = {},
        techFeatureEvidence = {},
        grooveStatsHash = hash,
        grooveStatsHashVersion = hashVersion,
        duplicateCopies = group and group.copyCount or 1,

        localPeer = localPeer,
        localScoring = localScoring,
    }

    for feature in pairs(curriculum().Tech or {}) do
        local evidence = techFeatureEvidence(
            candidateTech,
            candidateTechRaw,
            notation,
            feature
        )
        candidate.techFeatureEvidence[feature] = evidence
        candidate.techFeatureFits[feature] = evidence.fit
        candidate.techFeatureIntensity[feature] =
            evidence.intensity or 0
    end

    candidate.modeKey = "ForYou"
    candidate.section = SLRecommendations.Modes.ForYou.section
    candidate.reasons =
        recommendationReasons(
            candidate,
            SLRecommendations.Modes.ForYou.weights
        )

    return candidate
end

function SLRecommendations.BuildModel(pn, stepsType)
    stepsType = stepsType or GAMESTATE:GetCurrentStyle():GetStepsType()
    return buildModel(pn, stepsType)
end

local function shallowCopy(tableIn)
    local out = {}
    for key, value in pairs(tableIn) do
        out[key] = value
    end
    return out
end

local function techModeLevelFit(candidate, mode)
    if not mode
        or not mode.techFeature
        or not mode.techTargetMeter
    then
        return 0
    end

    return gaussian(
        candidate.meter - mode.techTargetMeter,
        math.max(
            0.50,
            tonumber(mode.techLevelSigma)
                or 1.75
        )
    )
end

local function weightedCandidateTotal(candidate, weights, mode)
    local numerator = 0
    local denominator = 0

    for name, weight in pairs(weights or {}) do
        if weight and weight > 0 then
            local value = candidate.components[name] or 0
            if name == "techFeature"
                and mode
                and mode.techFeature
            then
                -- Presence/evidence signal retained for compatibility.
                value =
                    candidate.techFeatureFits[
                        mode.techFeature
                    ] or 0

            elseif name == "techIntensity"
                and mode
                and mode.techFeature
            then
                value =
                    candidate.techFeatureIntensity[
                        mode.techFeature
                    ] or 0

            elseif name == "techLevelFit"
                and mode
                and mode.techFeature
            then
                value =
                    techModeLevelFit(
                        candidate,
                        mode
                    )

            elseif name == "techHistoryLevelFit"
                and mode
                and mode.techFeature
            then
                value =
                    techHistoryMeterFit(
                        candidate._model,
                        mode.techFeature,
                        candidate.meter
                    )

            elseif name == "quirkFeature" and mode and mode.quirkMode then
                value = candidate.components.quirkiness or 0

            elseif name == "rhythmFeature" and mode and mode.rhythmMode then
                value =
                    candidate.components.rhythmIntensity
                    or candidate.components.rhythmEvidence
                    or 0

            elseif name == "beginnerSafety" and mode and mode.techFeature then
                value = beginnerSafetyForTech(
                    candidate._model,
                    candidate.techVector,
                    mode.techFeature
                )
            end
            numerator = numerator + value * weight
            denominator = denominator + weight
        end
    end

    if denominator <= 0 then return 0 end
    return numerator / denominator
end

local function scoreForMode(model, baseCandidate, modeKey)
    local mode = getModeConfig(model, modeKey)
    local weights = getModeWeights(model, modeKey)

    -- Avoid a table allocation by temporarily attaching the model for the one
    -- mode-specific beginner-safety lookup above.
    baseCandidate._model = model
    local raw = weightedCandidateTotal(baseCandidate, weights, mode)
    baseCandidate._model = nil

    local floor = mode.difficultyGateFloor
        or SLRecommendations.Config.DifficultyGateFloor

    local fit
    if modeKey == "LevelUp" then
        fit = baseCandidate.components.levelUpFit
    elseif mode.techFeature then
        if mode.isInterestTech then
            -- A membership quota supplies progression coverage.  Do not
            -- multiply every result by a strong level-15-centered gate.
            fit = 1
        else
            fit =
                techModeLevelFit(
                    baseCandidate,
                    mode
                )
        end
    else
        fit = baseCandidate.components.difficulty
    end

    local gate = floor
    if fit ~= nil then
        gate = floor + (1 - floor) * fit
    end

    return raw, gate, raw * gate
end

local function rankedItemBetter(a, b)
    if not b then return true end
    if a.score ~= b.score then return a.score > b.score end
    if a.base.meter ~= b.base.meter then return a.base.meter < b.base.meter end
    return a.base.song:GetDisplayFullTitle():lower() < b.base.song:GetDisplayFullTitle():lower()
end

local function insertTopK(top, item, count)
    if count <= 0 then return end
    if #top >= count and not rankedItemBetter(item, top[#top]) then return end

    local low, high = 1, #top
    while low <= high do
        local mid = math.floor((low + high) / 2)
        if rankedItemBetter(item, top[mid]) then high = mid - 1 else low = mid + 1 end
    end
    table.insert(top, low, item)
    if #top > count then table.remove(top) end
end

local function materializeModeCandidate(model, item, modeKey)
    local mode = getModeConfig(model, modeKey)
    local weights = getModeWeights(model, modeKey)
    local candidate = shallowCopy(item.base)

    candidate.modeKey = modeKey
    candidate.section = getModeSection(model, modeKey)
    candidate.rawScore = item.rawScore
    candidate.difficultyGate = item.gate
    candidate.score = item.score

    local reasonComponents = shallowCopy(candidate.components)
    if mode.techFeature then
        reasonComponents.techFeature =
            candidate.techFeatureFits[
                mode.techFeature
            ] or 0

        reasonComponents.techIntensity =
            candidate.techFeatureIntensity[
                mode.techFeature
            ] or 0

        reasonComponents.techLevelFit =
            techModeLevelFit(
                candidate,
                mode
            )

        reasonComponents.techHistoryLevelFit =
            techHistoryMeterFit(
                model,
                mode.techFeature,
                candidate.meter
            )
    end
    local original = candidate.components
    candidate.components = reasonComponents
    candidate.reasons = recommendationReasons(candidate, weights)
    candidate.components = original

    return candidate
end

local function collapseModeToSongs(model, baseCandidates, modeKey, count)
    local mode = getModeConfig(model, modeKey)
    local bestBySong = {}

    for _, baseCandidate in ipairs(baseCandidates) do
        local allowed = true
        if mode.techFeature then
            local presence =
                baseCandidate.techFeatureFits[
                    mode.techFeature
                ] or 0

            local intensity =
                baseCandidate.techFeatureIntensity[
                    mode.techFeature
                ] or 0

            allowed =
                presence >=
                    (mode.requireTechFit or 0.40)
                and intensity >=
                    (
                        mode.requireTechIntensity
                        or 0.25
                    )

            if allowed
                and mode.isInterestTech
                and mode.techCeilingMeter
                and baseCandidate.meter > mode.techCeilingMeter
            then
                allowed = false
            end

        elseif mode.quirkMode then
            allowed = (baseCandidate.components.quirkiness or 0)
                >= (mode.requireQuirkiness or 0.42)

        elseif mode.rhythmMode then
            allowed =
                (baseCandidate.components.rhythmEvidence or 0)
                >= (mode.requireRhythm or 0.42)
        end

        if allowed then
            local rawScore, gate, score = scoreForMode(model, baseCandidate, modeKey)
            local item = {base = baseCandidate, rawScore = rawScore, gate = gate, score = score}
            local songKey = baseCandidate.song:GetSongDir()
            if not songKey or songKey == "" then
                songKey = baseCandidate.song:GetDisplayFullTitle() .. "\\0" .. baseCandidate.song:GetDisplayArtist()
            end
            local existing = bestBySong[songKey]
            if not existing or rankedItemBetter(item, existing) then bestBySong[songKey] = item end
        end
    end

    local resultLimit = count
    if mode.maxResults then
        resultLimit = math.min(resultLimit, mode.maxResults)
    end

    local top = {}

    if mode.isInterestTech
        and mode.techCeilingMeter
        and (mode.techCeilingQuota or 0) > 0
        and resultLimit > 0
    then
        local quota =
            math.max(
                1,
                math.floor(
                    resultLimit *
                    clamp(mode.techCeilingQuota, 0, 1)
                    + 0.5
                )
            )

        local band =
            math.max(
                0,
                tonumber(mode.techCeilingBand) or 1
            )

        local nearCeiling = {}
        local overall = {}

        for _, item in pairs(bestBySong) do
            insertTopK(overall, item, resultLimit)

            local meter = item.base.meter
            if meter <= mode.techCeilingMeter
                and meter >= (mode.techCeilingMeter - band)
            then
                insertTopK(nearCeiling, item, quota)
            end
        end

        local selectedSongs = {}

        for _, item in ipairs(nearCeiling) do
            if #top >= resultLimit then break end
            local songKey = tostring(item.base.song:GetSongDir())
            if not selectedSongs[songKey] then
                top[#top + 1] = item
                selectedSongs[songKey] = true
            end
        end

        for _, item in ipairs(overall) do
            if #top >= resultLimit then break end
            local songKey = tostring(item.base.song:GetSongDir())
            if not selectedSongs[songKey] then
                top[#top + 1] = item
                selectedSongs[songKey] = true
            end
        end

        -- Quota controls membership only; final display order remains scored.
        table.sort(top, function(a, b) return rankedItemBetter(a, b) end)
    else
        for _, item in pairs(bestBySong) do
            insertTopK(top, item, resultLimit)
        end
    end

    local results = {}
    for _, item in ipairs(top) do
        results[#results + 1] =
            materializeModeCandidate(model, item, modeKey)
    end
    return results
end

function SLRecommendations.GenerateModes(pn, options)
    options = options or {}

    local count =
        options.count
        or SLRecommendations.Config.WheelResultCount
        or 100

    local stepsType =
        options.stepsType
        or GAMESTATE:GetCurrentStyle():GetStepsType()

    local totalStart =
        GetTimeSinceStart and GetTimeSinceStart() or 0

    local modelStart = totalStart
    local model, err = buildModel(pn, stepsType)
    if not model then return {}, nil, err end

    local afterModel =
        GetTimeSinceStart and GetTimeSinceStart() or modelStart

    model.modelBuildSeconds =
        math.max(0, afterModel - modelStart)

    local baseCandidates = {}

    -- Score every unique chart ONCE.  All recommendation sections then reuse
    -- these features and only rerank with different weights.
    for _, group in ipairs(model._chartGroups or {}) do
        local rep = chooseRepresentative(group.entries, true)

        if rep then
            baseCandidates[#baseCandidates + 1] =
                scoreCandidate(model, rep, group)
        end
    end

    local afterCandidates =
        GetTimeSinceStart and GetTimeSinceStart() or afterModel

    model.candidateScoringSeconds =
        math.max(
            0,
            afterCandidates - afterModel
        )

    local resultsBySection = {}

    for _, modeKey in ipairs(model.modeOrder or SLRecommendations.ModeOrder) do
        local section = getModeSection(model, modeKey)
        resultsBySection[section] =
            collapseModeToSongs(
                model,
                baseCandidates,
                modeKey,
                count
            )
    end

    local afterRanking =
        GetTimeSinceStart and GetTimeSinceStart() or afterCandidates

    model.modeRankingSeconds =
        math.max(
            0,
            afterRanking - afterCandidates
        )

    model.rankingSeconds =
        model.candidateScoringSeconds +
        model.modeRankingSeconds

    model.totalGenerationSeconds =
        math.max(0, afterRanking - totalStart)

    return resultsBySection, model, nil
end

function SLRecommendations.Generate(pn, options)
    options = options or {}

    local resultsBySection, model, err =
        SLRecommendations.GenerateModes(
            pn,
            options
        )

    if err then return {}, model, err end

    local modeKey = options.mode or "ForYou"
    local section = getModeSection(model, modeKey)

    return resultsBySection[section] or {},
        model,
        nil
end

-- Lua can hand themes different userdata wrapper objects for the same
-- underlying C++ Song pointer across engine calls.  Do not use the userdata
-- object itself as a table key for persistent recommendation lookup.
local function recommendationSongKey(song)
    if not song then return nil end

    if song.GetSongDir then
        local dir = song:GetSongDir()
        if dir and dir ~= "" then
            return "dir:" .. dir
        end
    end

    -- Fallback should almost never be needed, but keeps this robust for
    -- profile-loaded/custom songs that may not have a normal directory.
    return table.concat({
        "meta",
        song:GetDisplayFullTitle() or "",
        song:GetDisplayArtist() or "",
    }, ":")
end

-- Store the current ranked set for theme/UI consumers.  This is intentionally
-- ephemeral; nothing here is written into Stats.xml.
SLRecommendations.Active = SLRecommendations.Active or {}

function SLRecommendations.SetActive(pn, resultsBySection, model)
    local key = ToEnumShortString(pn)

    -- Backward compatibility with older callers that passed one flat result
    -- array instead of section -> results.
    if resultsBySection
        and resultsBySection[1]
    then
        resultsBySection = {
            ["For You"] = resultsBySection,
        }
    end

    resultsBySection = resultsBySection or {}

    local bySectionSongKey = {}
    local bySectionChartHash = {}

    for section, results in pairs(resultsBySection) do
        local bySongKey = {}
        local byChartHash = {}

        for _, result in ipairs(results or {}) do
            local songKey =
                recommendationSongKey(result.song)

            if songKey then
                bySongKey[songKey] = result
            end

            local hash = result.grooveStatsHash
            if (not hash or hash == "") and result.steps then
                hash =
                    select(
                        1,
                        getGrooveStatsIdentity(result.steps)
                    )
            end

            if hash and hash ~= "" then
                byChartHash[hash] = result
            end
        end

        bySectionSongKey[section] = bySongKey
        bySectionChartHash[section] = byChartHash
    end

    SLRecommendations.Active[key] = {
        results =
            resultsBySection["For You"] or {},
        resultsBySection = resultsBySection,
        model = model,
        bySectionSongKey = bySectionSongKey,
        bySectionChartHash = bySectionChartHash,
    }
end

function SLRecommendations.GetActive(pn)
    return SLRecommendations.Active[
        ToEnumShortString(pn)
    ]
end

function SLRecommendations.ResolveRecommendationForSong(
    pn,
    song,
    section
)
    local active = SLRecommendations.GetActive(pn)

    if not active or not song then
        return nil, nil, "no-active-or-song"
    end

    section = section or "For You"

    local bySongKey =
        active.bySectionSongKey
        and active.bySectionSongKey[section]

    local byChartHash =
        active.bySectionChartHash
        and active.bySectionChartHash[section]

    if not bySongKey and not byChartHash then
        return nil, nil, "unknown-section"
    end

    local stepsType =
        active.model and active.model.stepsType
        or (
            GAMESTATE:GetCurrentStyle()
            and GAMESTATE:GetCurrentStyle():GetStepsType()
        )

    local function findLocalStepsForHash(hash)
        if not hash or hash == "" or not stepsType then
            return nil
        end

        for steps in ivalues(
            song:GetStepsByStepsType(stepsType) or {}
        ) do
            local localHash =
                select(
                    1,
                    getGrooveStatsIdentity(steps)
                )

            if localHash == hash then
                return steps
            end
        end

        return nil
    end

    if bySongKey then
        local songKey = recommendationSongKey(song)
        local direct =
            songKey and bySongKey[songKey] or nil

        if direct then
            local hash = direct.grooveStatsHash

            if (not hash or hash == "")
                and direct.steps
            then
                hash =
                    select(
                        1,
                        getGrooveStatsIdentity(
                            direct.steps
                        )
                    )
            end

            local localSteps =
                findLocalStepsForHash(hash)

            if localSteps then
                return direct,
                    localSteps,
                    "song-dir+hash"
            end

            if direct.steps then
                return direct,
                    direct.steps,
                    "song-dir-fallback"
            end
        end
    end

    if byChartHash and stepsType then
        for steps in ivalues(
            song:GetStepsByStepsType(stepsType) or {}
        ) do
            local hash =
                select(
                    1,
                    getGrooveStatsIdentity(steps)
                )

            local result =
                hash and byChartHash[hash] or nil

            if result then
                return result,
                    steps,
                    "groovestats-hash"
            end
        end
    end

    return nil, nil, "no-match"
end

function SLRecommendations.GetRecommendationForSong(
    pn,
    song,
    section
)
    local result =
        SLRecommendations.ResolveRecommendationForSong(
            pn,
            song,
            section
        )

    return result
end

function SLRecommendations.GetRecommendedStepsForSong(
    pn,
    song,
    section
)
    local _, steps =
        SLRecommendations.ResolveRecommendationForSong(
            pn,
            song,
            section
        )

    return steps
end

local function fmt(v, decimals)
    if v == nil then return "-" end
    return string.format("%." .. tostring(decimals or 3) .. "f", v)
end

function SLRecommendations.FormatDebug(results, model, resultsBySection)
    local lines = {}
    lines[#lines + 1] = "ITGmania / Simply Love Recommendation Prototype"
    lines[#lines + 1] = "================================================"
    lines[#lines + 1] = "Recommendation script version: " ..
        tostring(SLRecommendations.Version or "?")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Player maturity: " .. tostring(model.playerMaturity)
    lines[#lines + 1] = "Profile type: " .. tostring(model.profile and model.profile:GetType() or "nonpersistent")
    lines[#lines + 1] = "Personal data enabled: " .. tostring(model.usePersonalData)
    lines[#lines + 1] = "Personal-data confidence: " .. fmt(model.personalConfidence or 0, 3)
    lines[#lines + 1] = "Passed history charts: " .. tostring(model.passedHistoryCharts or 0)
    lines[#lines + 1] = "Working / reliable / mastered meter: " ..
        tostring(model.workingMeter or "-") .. " / " ..
        tostring(model.reliableMeter or "-") .. " / " ..
        tostring(model.masteredMeter or "-")
    lines[#lines + 1] = "Skill focus / Level Up target: " ..
        tostring(model.skillFocusLevel or "-") .. " / " ..
        tostring(model.levelUpMeter or "-")
    lines[#lines + 1] = "Score Well available: " .. tostring(model.scoreWellReady)
    lines[#lines + 1] = "Community favorite profiles: " .. tostring(model.communityFavoriteProfiles or 0)
    lines[#lines + 1] = "Played history charts: " .. tostring(model.playedHistoryCharts)
    lines[#lines + 1] = "Favorite songs: " .. tostring(model.favoriteSongs)
    lines[#lines + 1] = "Installed chart entries: " .. tostring(model.totalChartEntries)
    lines[#lines + 1] = "Unique chart identities: " .. tostring(model.uniqueChartIdentities)
    lines[#lines + 1] = "Duplicate GS hash groups: " .. tostring(model.duplicateHashGroups)
    lines[#lines + 1] = "Duplicate chart copies collapsed: " ..
        tostring(model.duplicateChartCopiesCollapsed)
    lines[#lines + 1] = "Learned meter center (weighted median): " ..
        (model.targetMeter and fmt(model.targetMeter, 2) or "(cold start)")
    lines[#lines + 1] = "Learned meter Q25-Q75: " ..
        (model.meterQ25 and fmt(model.meterQ25, 2) or "-") .. " - " ..
        (model.meterQ75 and fmt(model.meterQ75, 2) or "-")
    lines[#lines + 1] = "Difficulty sigma: " .. fmt(model.difficultySigma, 2)
    lines[#lines + 1] = "Max personal chart plays: " .. tostring(model.maxPlayerChartPlays)
    lines[#lines + 1] = "Max machine chart plays: " .. tostring(model.maxMachineChartPlays)
    lines[#lines + 1] = "StepsType: " .. tostring(model.stepsType)
    lines[#lines + 1] = "Model build time: " ..
        fmt(model.modelBuildSeconds or 0, 3) .. "s"
    lines[#lines + 1] = "Candidate scoring time: " ..
        fmt(model.candidateScoringSeconds or 0, 3) .. "s"
    lines[#lines + 1] = "Mode reranking/top-K time: " ..
        fmt(model.modeRankingSeconds or 0, 3) .. "s"
    lines[#lines + 1] = "Combined post-model ranking time: " ..
        fmt(model.rankingSeconds or 0, 3) .. "s"
    lines[#lines + 1] = "Total recommendation generation: " ..
        fmt(model.totalGenerationSeconds or 0, 3) .. "s"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Local peer scoring model:"
    lines[#lines + 1] = "  affects For You ranking: " ..
        tostring(SLRecommendations.Config.LocalPeerAffectsForYou)
    lines[#lines + 1] = "  Score Well section currently available: " .. tostring(model.scoreWellReady)
    lines[#lines + 1] = "  local/active profiles discovered: " ..
        tostring(
            model.localPeerDirectory
            and model.localPeerDirectory.profileCount
            or 0
        )
    lines[#lines + 1] = "  scalar HighScore profile-GUID binding observed: " ..
        tostring(
            model.localPeerDirectory
            and model.localPeerDirectory.profileGuidBindingSeen
            or false
        )
    lines[#lines + 1] = "  benchmark charts (min opponents met): " ..
        tostring(model.localPeerBenchmarkCharts or 0)

    local peerIdentityCount = 0
    for _ in pairs(model.localPeerObservedIdentities or {}) do
        peerIdentityCount = peerIdentityCount + 1
    end

    lines[#lines + 1] = "  unique peer identities observed: " ..
        tostring(peerIdentityCount)
    lines[#lines + 1] = "  GUID-backed opponent observations: " ..
        tostring(model.localPeerGuidOpponentObservations or 0)
    lines[#lines + 1] = "  name-only opponent observations: " ..
        tostring(model.localPeerNameOnlyOpponentObservations or 0)
    lines[#lines + 1] = "  failed/no-data scores excluded: " ..
        tostring(model.localPeerExcludedNonPassScores or 0)
    lines[#lines + 1] = "  current-player failed-only chart checks: " ..
        tostring(model.localPeerFailedOnlyCharts or 0)
    lines[#lines + 1] = "  average direct percentile: " ..
        (
            model.localPeerAveragePercentile
            and fmt(model.localPeerAveragePercentile * 100, 2) .. "%"
            or "-"
        )
    lines[#lines + 1] = "  average confidence-shrunk relative score: " ..
        (
            model.localPeerAverageRelative
            and fmt(model.localPeerAverageRelative, 3)
            or "-"
        )
    lines[#lines + 1] = "  unseen-chart predictor: " ..
        (
            model.localPeerRegression
            and "ridge regression"
            or "unavailable"
        )
    lines[#lines + 1] = "  regression training examples: " ..
        tostring(
            model.localPeerRegression
            and model.localPeerRegression.examples
            or 0
        )
    lines[#lines + 1] = "  regression RMSE: " ..
        (
            model.localPeerRegression
            and fmt(model.localPeerRegression.rmse, 4)
            or "-"
        )
    lines[#lines + 1] = "  regression global confidence: " ..
        (
            model.localPeerRegression
            and fmt(
                model.localPeerRegression.globalConfidence,
                3
            )
            or "-"
        )
    lines[#lines + 1] = "  regression feature count: " ..
        tostring(
            model.localPeerRegression
            and model.localPeerRegression.featureCount
            or 0
        )

    lines[#lines + 1] = ""
    lines[#lines + 1] =
        "Local scoring-difficulty model:"
    lines[#lines + 1] =
        "  affects Score Well ranking via localScoringEase: " ..
        tostring(
            SLRecommendations.Config.LocalScoringDifficultyAffectsRanking
        )
    lines[#lines + 1] =
        "  literal expected PercentDP affects ranking: false"

    if model.localScoringDifficulty then
        local s = model.localScoringDifficulty

        lines[#lines + 1] =
            "  passed-score observations: " ..
            tostring(s.observations or 0)
        lines[#lines + 1] =
            "  retained identities: " ..
            tostring(s.players or 0)
        lines[#lines + 1] =
            "  retained charts: " ..
            tostring(s.charts or 0)
        lines[#lines + 1] =
            "  population baseline expected score: " ..
            (
                s.baselineDp
                and fmt(s.baselineDp * 100, 2) .. "%"
                or "-"
            )
        lines[#lines + 1] =
            "  current-player ability term: " ..
            (
                s.currentAbility
                and fmt(s.currentAbility, 3)
                or "-"
            )
        lines[#lines + 1] =
            "  current-player baseline expected score: " ..
            (
                s.currentBaselineExpectedDp
                and fmt(
                    s.currentBaselineExpectedDp * 100,
                    2
                ) .. "%"
                or "-"
            )
        lines[#lines + 1] =
            "  chart difficulty robust center/scale: " ..
            fmt(s.difficultyCenter or 0, 3) ..
            " / " ..
            fmt(s.difficultyScale or 0, 3)
        lines[#lines + 1] =
            "  transformed-score RMSE: " ..
            (
                s.qualityRmse
                and fmt(s.qualityRmse, 4)
                or "-"
            )
        lines[#lines + 1] =
            "  PercentDP RMSE: " ..
            (
                s.dpRmse
                and fmt(s.dpRmse * 100, 2) .. "pp"
                or "-"
            )

        if model.localScoringDifficultyRegression then
            local r =
                model.localScoringDifficultyRegression

            lines[#lines + 1] =
                "  unseen-chart difficulty predictor: ridge regression"
            lines[#lines + 1] =
                "  difficulty regression examples: " ..
                tostring(r.examples or 0)
            lines[#lines + 1] =
                "  difficulty regression RMSE: " ..
                (
                    r.rmse
                    and fmt(r.rmse, 4)
                    or "-"
                )
            lines[#lines + 1] =
                "  difficulty regression confidence: " ..
                fmt(r.confidence or 0, 3)
        else
            lines[#lines + 1] =
                "  unseen-chart difficulty predictor: unavailable"
        end

        local rankedDifficulties = {}

        for chartKey, difficulty in pairs(
            s.difficulties or {}
        ) do
            local meta =
                s.chartMeta
                and s.chartMeta[chartKey]

            if meta then
                rankedDifficulties[
                    #rankedDifficulties + 1
                ] = {
                    title = meta.title,
                    meter = meta.meter,
                    difficulty = difficulty,
                    players =
                        #(
                            s.byChart[chartKey]
                            or {}
                        ),
                }
            end
        end

        table.sort(
            rankedDifficulties,
            function(a, b)
                return a.difficulty > b.difficulty
            end
        )

        if #rankedDifficulties > 0 then
            lines[#lines + 1] =
                "  hardest local scoring charts:"
            for i = 1, math.min(5, #rankedDifficulties) do
                local row =
                    rankedDifficulties[i]

                lines[#lines + 1] =
                    string.format(
                        "    + %s | m%d | difficulty=%s | players=%d",
                        row.title,
                        row.meter,
                        fmt(row.difficulty, 3),
                        row.players
                    )
            end

            lines[#lines + 1] =
                "  easiest local scoring charts:"

            for offset = 0,
                math.min(4, #rankedDifficulties - 1)
            do
                local row =
                    rankedDifficulties[
                        #rankedDifficulties - offset
                    ]

                lines[#lines + 1] =
                    string.format(
                        "    - %s | m%d | difficulty=%s | players=%d",
                        row.title,
                        row.meter,
                        fmt(row.difficulty, 3),
                        row.players
                    )
            end
        end
    else
        lines[#lines + 1] =
            "  unavailable"
    end
    lines[#lines + 1] = ""

    lines[#lines + 1] = "Tech curriculum state:"
    for feature, spec in pairs(curriculum().Tech or {}) do
        local stat = model.techMastery[feature]
        if stat then
            local meterPairs = {}
            for meter, weight in pairs(stat.meterWeights or {}) do
                meterPairs[#meterPairs + 1] = {
                    meter = meter,
                    weight = weight,
                }
            end

            table.sort(
                meterPairs,
                function(a, b)
                    return a.weight > b.weight
                end
            )

            local meterSummary = {}
            for i = 1, math.min(4, #meterPairs) do
                meterSummary[#meterSummary + 1] =
                    tostring(meterPairs[i].meter)
                    .. ":"
                    .. fmt(meterPairs[i].weight, 1)
            end

            lines[#lines + 1] = string.format(
                "  %s: mastered=%s | qualifying=%d | median=%s | recentCharts=%d | recentInterest=%s | preferredMeters=%s",
                tostring(spec.label or feature),
                tostring(stat.mastered),
                stat.qualifying or 0,
                stat.median and (fmt(stat.median * 100, 1) .. "%") or "-",
                stat.recentCharts or 0,
                fmt(stat.recentInterest or 0, 3),
                #meterSummary > 0
                    and table.concat(meterSummary, ",")
                    or "-"
            )
        end
    end
    lines[#lines + 1] = "Rhythm profile:"
    lines[#lines + 1] =
        "  Chaos rhythm threshold/full: " ..
        fmt(
            tonumber(
                (curriculum().Rhythms or {}).chaosThreshold
            ) or 1.20,
            2
        ) ..
        " / " ..
        fmt(
            tonumber(
                (curriculum().Rhythms or {}).chaosFull
            ) or 2.25,
            2
        )

    lines[#lines + 1] =
        "  recent rhythm charts: " ..
        tostring(
            model.recentRhythmCharts
            or 0
        )

    lines[#lines + 1] =
        "  recent rhythm interest: " ..
        fmt(
            model.recentRhythmInterest
            or 0,
            3
        )

    lines[#lines + 1] =
        "  passed rhythm charts: " ..
        tostring(
            model.rhythmPassedCharts
            or 0
        )

    lines[#lines + 1] =
        "  passed rhythm median: " ..
        (
            model.rhythmPassedMedian
            and (
                fmt(
                    model.rhythmPassedMedian * 100,
                    1
                )
                .. "%"
            )
            or "-"
        )

    lines[#lines + 1] =
        "  rhythm familiarity: " ..
        fmt(
            model.rhythmFamiliarity
            or 0,
            3
        )

    lines[#lines + 1] = ""

    lines[#lines + 1] = "Quirkiness profile:"
    lines[#lines + 1] = "  historical target: " .. fmt(model.targetQuirkiness or 0, 3)
    lines[#lines + 1] = "  recent quirky charts: " .. tostring(model.recentQuirkCharts or 0)
    lines[#lines + 1] = "  recent quirk interest: " .. fmt(model.recentQuirkInterest or 0, 3)
    lines[#lines + 1] = "  FGChanges binding available: " .. tostring(
        model._chartGroups and model._chartGroups[1]
        and model._chartGroups[1].representative
        and model._chartGroups[1].representative.song.GetFGChanges ~= nil
        or false
    )
    lines[#lines + 1] = ""

    lines[#lines + 1] = ""

    if model.targetStamina then
        lines[#lines + 1] = "Learned stamina/density profile:"
        lines[#lines + 1] = string.format(
            "  duration=%ss | peakNPS=%s | radar S/V/A/F/C=%s/%s/%s/%s/%s",
            fmt(
                math.exp(model.targetStamina.logDuration or 0) - 1,
                1
            ),
            fmt(
                math.exp(model.targetStamina.logPeakNps or 0) - 1,
                2
            ),
            fmt(model.targetStamina.radarStream or 0, 3),
            fmt(model.targetStamina.radarVoltage or 0, 3),
            fmt(model.targetStamina.radarAir or 0, 3),
            fmt(model.targetStamina.radarFreeze or 0, 3),
            fmt(model.targetStamina.radarChaos or 0, 3)
        )
        lines[#lines + 1] = string.format(
            "  density sustain=%s | highFraction=%s | runFraction=%s | activeFraction=%s",
            fmt(model.targetStamina.densitySustainRatio or 0, 3),
            fmt(model.targetStamina.densityHighFraction or 0, 3),
            fmt(model.targetStamina.densityRunFraction or 0, 3),
            fmt(model.targetStamina.activeMeasureFraction or 0, 3)
        )
    end

    if #(model.localPeerExamples or {}) > 0 then
        local examples = {}
        for _, example in ipairs(model.localPeerExamples) do
            examples[#examples + 1] = example
        end

        table.sort(examples, function(a, b)
            if a.relative == b.relative then
                return a.confidence > b.confidence
            end
            return a.relative > b.relative
        end)

        lines[#lines + 1] = "  strongest local-relative benchmark charts:"
        for i = 1, math.min(5, #examples) do
            local e = examples[i]
            lines[#lines + 1] = string.format(
                "    + %s | m%d | rel=%s | pct=%s | gap=%+.2fpp | opponents=%d | conf=%s",
                e.title,
                e.meter,
                fmt(e.relative, 3),
                fmt(e.percentile * 100, 1) .. "%",
                e.gap * 100,
                e.opponents,
                fmt(e.confidence, 2)
            )
        end

        lines[#lines + 1] = "  weakest local-relative benchmark charts:"
        for offset = 0, math.min(4, #examples - 1) do
            local e = examples[#examples - offset]
            lines[#lines + 1] = string.format(
                "    - %s | m%d | rel=%s | pct=%s | gap=%+.2fpp | opponents=%d | conf=%s",
                e.title,
                e.meter,
                fmt(e.relative, 3),
                fmt(e.percentile * 100, 1) .. "%",
                e.gap * 100,
                e.opponents,
                fmt(e.confidence, 2)
            )
        end
    end

    lines[#lines + 1] = ""

    if resultsBySection then
        lines[#lines + 1] = "Recommendation section previews:"
        for _, modeKey in ipairs(model.modeOrder or SLRecommendations.ModeOrder) do
            local section = getModeSection(model, modeKey)
            local modeResults =
                resultsBySection[section] or {}

            lines[#lines + 1] =
                "  [" .. section .. "] (" .. tostring(#modeResults) .. " results)"

            local previewMode = getModeConfig(model, modeKey)
            for i = 1, math.min(10, #modeResults) do
                local r = modeResults[i]
                lines[#lines + 1] = string.format(
                    "    %02d. %s | m%d | score=%s | peer=%s | localEase=%s | expectedLocal=%s | pop=%s | recent=%s | localFav=%s | beginner=%s | quirk=%s | rhythm=%s | chaos=%s | metadata=%s | tech=%s | stamina=%s",
                    i,
                    r.song:GetDisplayFullTitle(),
                    r.meter,
                    fmt(r.score, 4),
                    fmt(
                        r.components.localPeerPerformance,
                        3
                    ),
                    fmt(
                        r.components.localScoringEase,
                        3
                    ),
                    r.localScoring
                        and (
                            fmt(
                                r.localScoring.shrunkExpectedDp * 100,
                                2
                            ) .. "%"
                        )
                        or "-",
                    fmt(r.components.popularity, 3),
                    fmt(r.components.machineRecentActivity, 3),
                    fmt(r.components.communityFavorite, 3),
                    fmt(r.components.beginnerSafety, 3),
                    fmt(r.components.quirkiness, 3),
                    fmt(r.components.rhythmEvidence, 3),
                    fmt(
                        r.chartShape
                        and r.chartShape.radarChaos
                        or 0,
                        3
                    ),
                    fmt(r.components.metadata, 3),
                    fmt(r.components.tech, 3),
                    fmt(r.components.stamina, 3)
                )

                if previewMode.techFeature then
                    local evidence = r.techFeatureEvidence
                        and r.techFeatureEvidence[previewMode.techFeature]
                    if evidence then
                        lines[#lines + 1] = string.format(
                            "        targetTech=%s | presence=%s | intensity=%s | targetMeter=%s | ceiling=%s | levelFit=%s | historyLevelFit=%s | engineCount=%d | engineRate=%s/min | engineIntensity=%s | notation=%s | notationStrength=%s | notationIntensity=%s",
                            tostring(
                                previewMode.techFeature
                            ),
                            fmt(
                                evidence.fit,
                                3
                            ),
                            fmt(
                                evidence.intensity or 0,
                                3
                            ),
                            tostring(
                                previewMode.techTargetMeter
                                or "-"
                            ),
                            tostring(
                                previewMode.techCeilingMeter
                                or "-"
                            ),
                            fmt(
                                techModeLevelFit(
                                    r,
                                    previewMode
                                ),
                                3
                            ),
                            fmt(
                                techHistoryMeterFit(
                                    model,
                                    previewMode.techFeature,
                                    r.meter
                                ),
                                3
                            ),
                            evidence.engineCount or 0,
                            fmt(
                                evidence.engineRate,
                                2
                            ),
                            fmt(
                                evidence.engineIntensity or 0,
                                3
                            ),
                            evidence.notationToken or "-",
                            fmt(
                                evidence.notationStrength
                                    or 0,
                                2
                            ),
                            fmt(
                                evidence.notationIntensity
                                    or 0,
                                2
                            )
                        )
                    end
                elseif previewMode.quirkMode and r.quirkiness then
                    lines[#lines + 1] = string.format(
                        "        quirkEvidence: points=%s | reasons=%s",
                        fmt(r.quirkiness.points, 2),
                        table.concat(r.quirkiness.reasons or {}, "; ")
                    )

                elseif previewMode.rhythmMode and r.rhythm then
                    lines[#lines + 1] = string.format(
                        "        rhythmEvidence: fit=%s | intensity=%s | chaos=%s | chaosPresence=%s | notation=%s | notationStrength=%s | streamNotation=%s",
                        fmt(r.rhythm.evidence or 0, 3),
                        fmt(r.rhythm.intensity or 0, 3),
                        fmt(r.rhythm.chaos or 0, 3),
                        fmt(r.rhythm.chaosPresence or 0, 3),
                        r.rhythm.notationToken or "-",
                        fmt(r.rhythm.notationStrength or 0, 2),
                        fmt(r.rhythm.streamNotationStrength or 0, 2)
                    )
                end
            end
        end

        lines[#lines + 1] = ""
        lines[#lines + 1] =
            "Detailed For You results:"
        lines[#lines + 1] = ""
    end

    for i, r in ipairs(results) do
        lines[#lines + 1] = string.format(
            "%02d. %s | meter %d | score %.4f | raw %.4f | gate %.3f",
            i,
            r.song:GetDisplayFullTitle(),
            r.meter,
            r.score,
            r.rawScore,
            r.difficultyGate
        )

        lines[#lines + 1] = string.format(
            "    artist=%s | stepartist=%s | genre=%s | favorite=%s | plays=%d | machine=%d | bestDP=%s | peakNPS=%s",
            r.artist ~= "" and r.artist or "-",
            r.credit ~= "" and r.credit or "-",
            r.genre ~= "" and r.genre or "-",
            tostring(r.favorite),
            r.playerPlays,
            r.machinePlays,
            r.bestPercentDP and fmt(r.bestPercentDP * 100, 2) .. "%" or "-",
            fmt(r.peakNps, 2)
        )

        lines[#lines + 1] = string.format(
            "    recency: personalDays=%s | machineDays=%s | gsHash=%s | hashVersion=%s | installedCopies=%d",
            r.personalDaysSince and fmt(r.personalDaysSince, 1) or "-",
            r.machineDaysSince and fmt(r.machineDaysSince, 1) or "-",
            r.grooveStatsHash or "-",
            r.grooveStatsHashVersion ~= nil and tostring(r.grooveStatsHashVersion) or "-",
            r.duplicateCopies or 1
        )

        if r.chartShape then
            lines[#lines + 1] = string.format(
                "    shape: duration=%ss | peakNPS=%s | radar S/V/A/F/C=%s/%s/%s/%s/%s | density mean=%s sustain=%s high=%s run=%s active=%s",
                fmt(r.chartShape.durationSeconds or 0, 1),
                fmt(r.chartShape.peakNps or 0, 2),
                fmt(r.chartShape.radarStream or 0, 3),
                fmt(r.chartShape.radarVoltage or 0, 3),
                fmt(r.chartShape.radarAir or 0, 3),
                fmt(r.chartShape.radarFreeze or 0, 3),
                fmt(r.chartShape.radarChaos or 0, 3),
                fmt(r.chartShape.densityMeanActiveNps or 0, 2),
                fmt(r.chartShape.densitySustainRatio or 0, 3),
                fmt(r.chartShape.densityHighFraction or 0, 3),
                fmt(r.chartShape.densityRunFraction or 0, 3),
                fmt(r.chartShape.activeMeasureFraction or 0, 3)
            )
        end

        if r.chartNotation and r.chartNotation.source ~= "" then
            lines[#lines + 1] =
                "    notation: " .. r.chartNotation.source
        end

        if r.quirkiness then
            lines[#lines + 1] = string.format(
                "    quirk: score=%s | points=%s | Edit=%s | FG=%d | BG=%d | BPM=%d | speed=%d | scroll=%d | mines=%d | lifts=%d | fakes=%d | reasons=%s",
                fmt(r.quirkiness.score, 3),
                fmt(r.quirkiness.points, 2),
                tostring(r.quirkiness.isEdit or false),
                r.quirkiness.fgCount or 0,
                r.quirkiness.bgCount or 0,
                r.quirkiness.bpmCount or 0,
                r.quirkiness.speedCount or 0,
                r.quirkiness.scrollCount or 0,
                r.quirkiness.mines or 0,
                r.quirkiness.lifts or 0,
                r.quirkiness.fakeCount or 0,
                table.concat(r.quirkiness.reasons or {}, "; ")
            )
        end

        if r.rhythm then
            lines[#lines + 1] = string.format(
                "    rhythm: evidence=%s | intensity=%s | complexity=%s | chaos=%s | chaosPresence=%s | notation=%s | notationStrength=%s | streamNotation=%s | safety=%s",
                fmt(r.rhythm.evidence or 0, 3),
                fmt(r.rhythm.intensity or 0, 3),
                fmt(r.rhythm.complexity or 0, 3),
                fmt(r.rhythm.chaos or 0, 3),
                fmt(r.rhythm.chaosPresence or 0, 3),
                r.rhythm.notationToken or "-",
                fmt(r.rhythm.notationStrength or 0, 2),
                fmt(r.rhythm.streamNotationStrength or 0, 2),
                fmt(r.components.rhythmSafety or 1, 3)
            )
        end

        if r.localScoring then
            lines[#lines + 1] = string.format(
                "    localScoring: ease=%s | rawEase=%s | difficultyZ=%s | expected=%s | rawExpected=%s | chartDifficulty=%s | conf=%s | source=%s",
                fmt(
                    r.localScoring.ease,
                    3
                ),
                fmt(
                    r.localScoring.rawEase,
                    3
                ),
                fmt(
                    r.localScoring.difficultyZ,
                    2
                ),
                fmt(
                    r.localScoring.shrunkExpectedDp * 100,
                    2
                ) .. "%",
                fmt(
                    r.localScoring.expectedDp * 100,
                    2
                ) .. "%",
                fmt(
                    r.localScoring.difficulty,
                    3
                ),
                fmt(
                    r.localScoring.confidence,
                    3
                ),
                tostring(
                    r.localScoring.source
                    or "-"
                )
            )
        else
            lines[#lines + 1] =
                "    localScoring: unavailable"
        end

        if r.localPeer then
            lines[#lines + 1] = string.format(
                "    localPeer: fit=%s | raw=%s | conf=%s | source=%s | opponents=%s | neighbors=%s | percentile=%s | gap=%s",
                fmt(r.localPeer.fit, 3),
                fmt(r.localPeer.raw, 3),
                fmt(r.localPeer.confidence, 3),
                tostring(r.localPeer.source or "-"),
                r.localPeer.opponents and tostring(r.localPeer.opponents) or "-",
                r.localPeer.neighbors and tostring(r.localPeer.neighbors) or "-",
                r.localPeer.percentile and (fmt(r.localPeer.percentile * 100, 1) .. "%") or "-",
                r.localPeer.gap and (fmt(r.localPeer.gap * 100, 2) .. "pp") or "-"
            )

            if r.localPeer.source == "regression" then
                lines[#lines + 1] = string.format(
                    "      regression: maxAbsZ=%s",
                    r.localPeer.maxAbsZ
                        and fmt(r.localPeer.maxAbsZ, 2)
                        or "-"
                )
            end
        else
            lines[#lines + 1] =
                "    localPeer: unavailable"
        end

        local componentParts = {}
        for name, value in pairs(r.components) do
            componentParts[#componentParts + 1] = name .. "=" .. fmt(value, 3)
        end
        table.sort(componentParts)
        lines[#lines + 1] = "    components: " .. table.concat(componentParts, ", ")
        lines[#lines + 1] = "    reasons: " ..
            (#r.reasons > 0 and table.concat(r.reasons, "; ") or "none above explanation threshold")
        lines[#lines + 1] = ""
    end

    return table.concat(lines, "\n")
end

function SLRecommendations.WriteDebugFile(
    pn,
    results,
    model,
    resultsBySection
)
    if not resultsBySection then
        local active =
            SLRecommendations.GetActive(pn)

        resultsBySection =
            active and active.resultsBySection or nil
    end

    local path
    if PROFILEMAN:IsPersistentProfile(pn) then
        path = PROFILEMAN:GetProfileDir(profileSlotForPlayer(pn)) .. "recommendations-debug.txt"
    else
        path = PROFILEMAN:GetProfileDir("ProfileSlot_Machine") .. "recommendations-guest-debug.txt"
    end
    local file = RageFileUtil.CreateRageFile()
    if not file:Open(path, 2) then
        file:destroy()
        return false
    end

    file:Write(
        SLRecommendations.FormatDebug(
            results,
            model,
            resultsBySection
        )
    )
    file:Close()
    file:destroy()
    return true
end
