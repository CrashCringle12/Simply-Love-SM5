-- ITGmania / Simply Love Recommendations module
-- v24.5
--
-- Target:
--   ITGmania beta
--   Simply Love itgmania-beta
--
-- Module lifecycle:
--   The root ScreenSelectMusic actor is initialized from ModuleCommand.
--   Visual child actors use normal InitCommand, matching existing Simply Love
--   modules such as bpm_change_indicator.lua.

local t = {}
local MODULE_VERSION = "24.5"

local TARGET_SCREEN = "ScreenSelectMusic"

local installAttempts = 0
local dailyInitAttempts = 0
local activePlayer = nil
local dailyPreparationInProgress = false

local function isRecommendationScreen()
    local screen =
        SCREENMAN
        and SCREENMAN:GetTopScreen()
        or nil

    return
        screen ~= nil
        and screen:GetName() == TARGET_SCREEN
end

-- -------------------------------------------------------------------------
-- UI geometry
-- -------------------------------------------------------------------------
-- Reuse the same left-side boundary math as the PSU-cabby ITL nearby
-- leaderboard so the recommendation panel occupies otherwise-unused space
-- without covering the song banner.  On narrow/4:3 layouts where that region
-- effectively does not exist, the panel hides and the difficulty marker still
-- provides the important recommendation cue.
local function recommendationPanelGeometry()
    local bannerY = 96
    local bannerHeight = 164
    local bannerZoom = IsUsingWideScreen() and 0.7655 or 0.72
    local bannerCenterX =
        IsUsingWideScreen()
        and (_screen.cx - 170)
        or (_screen.cx - 160)

    local bannerEffW = 418 * bannerZoom
    local bannerLeftEdge = bannerCenterX - bannerEffW / 2
    local width = math.floor(bannerLeftEdge - 10)
    local top =
        bannerY -
        (bannerHeight * bannerZoom) / 2 +
        8

    return {
        available = width >= 72,
        x = 6,
        y = top,
        width = math.max(72, width - 6),
        height = 208,
    }
end

local PANEL = recommendationPanelGeometry()

local function recommendationBannerStarGeometry()
    local bannerY = 96
    local bannerHeight = 164
    local bannerZoom = IsUsingWideScreen() and 0.7655 or 0.72
    local bannerCenterX =
        IsUsingWideScreen()
        and (_screen.cx - 170)
        or (_screen.cx - 160)

    local bannerEffW = 418 * bannerZoom
    local bannerEffH = bannerHeight * bannerZoom

    return {
        x = bannerCenterX - bannerEffW / 2 + 13,
        y = bannerY - bannerEffH / 2 + 13,
    }
end

local BANNER_STAR = recommendationBannerStarGeometry()

local function starVertices(outerRadius, innerRadius)
    local points = {}

    for i = 0, 9 do
        local radius = (i % 2 == 0) and outerRadius or innerRadius
        local angle = -math.pi / 2 + i * math.pi / 5
        points[#points + 1] = {
            radius * math.cos(angle),
            radius * math.sin(angle),
        }
    end

    local verts = {}
    for i = 1, 10 do
        local nextIndex = (i % 10) + 1
        verts[#verts + 1] = {{0, 0, 0}, {1,1,1,1}}
        verts[#verts + 1] = {{points[i][1], points[i][2], 0}, {1,1,1,1}}
        verts[#verts + 1] = {{points[nextIndex][1], points[nextIndex][2], 0}, {1,1,1,1}}
    end

    return verts
end

local function recommendationAccentColor()
    local raw = "#F4D35E"

    if SLRecommendations
        and SLRecommendations.Config
        and SLRecommendations.Config.RecommendationUIAccentColor ~= nil
    then
        raw = SLRecommendations.Config.RecommendationUIAccentColor
    end

    if type(raw) == "string" then
        return color(raw)
    end

    return raw or Color.White
end

local function isITLOnlineSong()
    local song = GAMESTATE:GetCurrentSong()
    if not song then return false end

    local group = tostring(song:GetGroupName() or ""):lower()
    return group:find("itl online", 1, true) ~= nil
end

local function sameSteps(a, b)
    if not a or not b then return false end
    if a == b then return true end

    local hashA = a:GetGrooveStatsHash() or ""
    local hashB = b:GetGrooveStatsHash() or ""

    if hashA ~= "" and hashB ~= "" and hashA == hashB then
        return true
    end

    return
        a:GetDifficulty() == b:GetDifficulty()
        and a:GetMeter() == b:GetMeter()
        and (a:GetChartName() or "") == (b:GetChartName() or "")
        and (a:GetDescription() or "") == (b:GetDescription() or "")
end

-- This mirrors Simply Love's StepsDisplayList/StepsToDisplay.lua closely
-- enough to find the row occupied by the recommended Steps, including edits.
local function visibleStepsInDifficultyGrid(song)
    if not song then return {} end

    local allSteps = SongUtil.GetPlayableSteps(song) or {}
    local stepsToShow = {}
    local edits = {}

    for stepchart in ivalues(allSteps) do
        local difficulty = stepchart:GetDifficulty()

        if difficulty == "Difficulty_Edit" then
            edits[#edits + 1] = stepchart
        else
            stepsToShow[
                Difficulty:Reverse()[difficulty] + 1
            ] = stepchart
        end
    end

    if #edits == 0 then
        return stepsToShow
    end

    local humans = GAMESTATE:GetHumanPlayers()

    if #humans <= 1 then
        local player = humans[1]
        local current =
            player
            and GAMESTATE:GetCurrentSteps(player)
            or nil

        if not current or not current:IsAnEdit() then
            return stepsToShow
        end
    else
        local p1 = GAMESTATE:GetCurrentSteps(PLAYER_1)
        local p2 = GAMESTATE:GetCurrentSteps(PLAYER_2)

        if (not p1 or not p1:IsAnEdit())
            and (not p2 or not p2:IsAnEdit())
        then
            return stepsToShow
        end
    end

    for i, edit in ipairs(edits) do
        stepsToShow[5 + i] = edit
    end

    if #humans <= 1 then
        local current = GAMESTATE:GetCurrentSteps(humans[1])
        local editIndex = 0

        for i, edit in ipairs(edits) do
            if sameSteps(edit, current) then
                editIndex = i
                break
            end
        end

        return {
            stepsToShow[1 + editIndex],
            stepsToShow[2 + editIndex],
            stepsToShow[3 + editIndex],
            stepsToShow[4 + editIndex],
            stepsToShow[5 + editIndex],
        }
    end

    local indexP1 = nil
    local indexP2 = nil

    for i, stepchart in pairs(stepsToShow) do
        if sameSteps(
            stepchart,
            GAMESTATE:GetCurrentSteps(PLAYER_1)
        ) then
            indexP1 = i
        end

        if sameSteps(
            stepchart,
            GAMESTATE:GetCurrentSteps(PLAYER_2)
        ) then
            indexP2 = i
        end
    end

    if indexP1 and indexP2 then
        local lesserIndex = math.min(indexP1, indexP2)
        local greaterIndex = math.max(indexP1, indexP2)

        if math.abs(indexP1 - indexP2) >= 5 then
            return {
                stepsToShow[lesserIndex],
                stepsToShow[lesserIndex + 1],
                stepsToShow[lesserIndex + 2],
                stepsToShow[greaterIndex - 1],
                stepsToShow[greaterIndex],
            }
        end

        return {
            stepsToShow[greaterIndex - 4],
            stepsToShow[greaterIndex - 3],
            stepsToShow[greaterIndex - 2],
            stepsToShow[greaterIndex - 1],
            stepsToShow[greaterIndex],
        }
    end

    return stepsToShow
end

local function recommendedDifficultyGridRow(targetSteps)
    local song = GAMESTATE:GetCurrentSong()
    if not song or not targetSteps then return nil end

    local rows = visibleStepsInDifficultyGrid(song)

    for i = 1, 5 do
        if sameSteps(rows[i], targetSteps) then
            return i
        end
    end

    return nil
end

local function cfg(name, default)
    if not SLRecommendations or not SLRecommendations.Config then
        return default
    end

    local value = SLRecommendations.Config[name]
    if value == nil then
        return default
    end

    return value
end

local function dbg(msg)
    if not cfg("RecommendationUIDebug", false) then
        return
    end

    local line = "[Recommendations] " .. tostring(msg)
    Trace(line)

    if cfg("RecommendationUIDebugOnScreen", false) and SM then
        SM(line, 6, true)
    end
end

local function recommendationsAvailable()
    if not isRecommendationScreen() then
        return false
    end

    if GAMESTATE:IsCourseMode() then return false end

    -- Guest/no-data players are valid recommendation users now.  The engine
    -- decides whether the player is guest/cold/developing/established.
    return #GAMESTATE:GetHumanPlayers() > 0
end

local function getSortMenuContext()
    if not isRecommendationScreen() then
        return nil
    end

    local screen = SCREENMAN:GetTopScreen()
    if not screen then return nil end

    local overlay = screen:GetChild("Overlay")
    if not overlay then return nil end

    local sortmenu = overlay:GetChild("SortMenu")
    if not sortmenu then return nil end

    return {
        screen = screen,
        overlay = overlay,
        sortmenu = sortmenu,
    }
end

local function customSortOptionExists(sortmenu, key)
    for _, option in ipairs(sortmenu.wheel_options or {}) do
        if type(option) == "table"
            and type(option[1]) == "table"
            and option[1][2] == "CategoryProfile"
            and type(option[2]) == "table"
        then
            for _, suboption in ipairs(option[2]) do
                if type(suboption) == "table"
                    and type(suboption[1]) == "table"
                    and suboption[1][2] == key
                then
                    return true
                end
            end
        end
    end

    return false
end

local function injectRecommendedOption()
    local ctx = getSortMenuContext()
    if not ctx then return false end

    local hasRecommendations =
        customSortOptionExists(ctx.sortmenu, "Recommendations")
    local hasRefresh =
        customSortOptionExists(ctx.sortmenu, "RefreshRecommendations")

    for _, option in ipairs(ctx.sortmenu.wheel_options or {}) do
        if type(option) == "table"
            and type(option[1]) == "table"
            and option[1][2] == "CategoryProfile"
            and type(option[2]) == "table"
        then
            if not hasRecommendations then
                table.insert(option[2], {
                    {"For You", "Recommendations"},
                    recommendationsAvailable,
                })
            end

            if not hasRefresh then
                table.insert(option[2], {
                    {"Refresh Recommendations", "RefreshRecommendations"},
                    recommendationsAvailable,
                })
            end

            dbg("Recommendation SortMenu options ready.")
            return true
        end
    end

    if not hasRecommendations then
        table.insert(ctx.sortmenu.wheel_options, {
            {"For You", "Recommendations"},
            recommendationsAvailable,
        })
    end

    if not hasRefresh then
        table.insert(ctx.sortmenu.wheel_options, {
            {"Refresh Recommendations", "RefreshRecommendations"},
            recommendationsAvailable,
        })
    end

    dbg("CategoryProfile not found; inserted top-level recommendation options.")
    return true
end

local function currentPreferredSection()
    local ctx = getSortMenuContext()
    if not ctx then return nil end

    local section =
        ctx.screen:GetMusicWheel():GetSelectedSection()

    if section and section ~= "" then
        return section
    end

    local song = GAMESTATE:GetCurrentSong()
    if song then
        return SONGMAN:SongToPreferredSortSectionName(song)
    end

    return nil
end

local function anyRecommendationForSong(song)
    if not isRecommendationScreen() then
        return nil
    end

    if not song or not activePlayer then return nil end

    local active = SLRecommendations.GetActive(activePlayer)
    if not active or not active.bySectionSongKey then return nil end

    local dir = song:GetSongDir()
    local songKey

    if dir and dir ~= "" then
        songKey = "dir:" .. dir
    else
        songKey = table.concat({
            "meta",
            song:GetDisplayFullTitle() or "",
            song:GetDisplayArtist() or "",
        }, ":")
    end

    for section, bySong in pairs(active.bySectionSongKey) do
        local result = bySong[songKey]
        if result then return result, section end
    end

    return nil
end

local function recommendationRank(result, section)
    if not result or not activePlayer then return nil end

    local active = SLRecommendations.GetActive(activePlayer)
    if not active or not active.resultsBySection then
        return nil
    end

    section = section or currentPreferredSection()

    local results =
        section and active.resultsBySection[section] or nil

    if not results then return nil end

    for i, candidate in ipairs(results) do
        if candidate == result then
            return i
        end
    end

    return nil
end

local function describeSteps(steps)
    if not steps then return "nil" end

    local hash = steps:GetGrooveStatsHash() or ""
    return string.format(
        "meter=%s diff=%s hash=%s credit=%s",
        tostring(steps:GetMeter()),
        tostring(steps:GetDifficulty()),
        tostring(hash),
        tostring(steps:GetAuthorCredit() or "")
    )
end

local function resolveCurrentRecommendation(verbose)
    if not isRecommendationScreen() then
        if verbose then
            dbg("resolve: not on ScreenSelectMusic")
        end

        return nil, nil, "wrong-screen"
    end

    if not activePlayer then
        if verbose then dbg("resolve: activePlayer=nil") end
        return nil, nil, "no-player"
    end

    local song = GAMESTATE:GetCurrentSong()
    if not song then
        if verbose then dbg("resolve: current song=nil") end
        return nil, nil, "no-song"
    end

    local sort = GAMESTATE:GetSortOrder()
    local section = currentPreferredSection()

    if verbose then
        dbg(string.format(
            "resolve: sort=%s section=%s song=%s dir=%s",
            tostring(sort),
            tostring(section),
            tostring(song:GetDisplayFullTitle()),
            tostring(song:GetSongDir())
        ))
    end

    if sort ~= "SortOrder_Preferred" then
        return nil, nil, "not-preferred"
    end

    local active =
        SLRecommendations.GetActive(activePlayer)

    if not active
        or not active.resultsBySection
        or not section
        or not active.resultsBySection[section]
    then
        return nil, nil, "not-recommendations-section"
    end

    local result, localSteps, resolution =
        SLRecommendations.ResolveRecommendationForSong(
            activePlayer,
            song,
            section
        )

    if verbose then
        dbg(
            "resolve result=" .. tostring(result ~= nil) ..
            " localSteps=" .. tostring(localSteps ~= nil) ..
            " via=" .. tostring(resolution)
        )

        if result then
            dbg(
                "ranked target: " ..
                tostring(result.song:GetDisplayFullTitle()) ..
                " | " .. describeSteps(result.steps)
            )
        end

        if localSteps then
            dbg("local target: " .. describeSteps(localSteps))
        end
    end

    return result, localSteps, resolution
end

local function preferredSectionsFromResults(resultsBySection)
    local preferredSections = {}

    for section, results in pairs(resultsBySection or {}) do
        local songs = {}
        for _, result in ipairs(results) do
            songs[#songs + 1] = result.song
        end
        if #songs > 0 then preferredSections[section] = songs end
    end

    return preferredSections
end

local function prepareRecommendations(forceRefresh, switchToRecommendedSort)
    if not isRecommendationScreen() then
        dbg(
            "prepareRecommendations ignored on " ..
            tostring(
                SCREENMAN
                and SCREENMAN:GetTopScreen()
                and SCREENMAN:GetTopScreen():GetName()
                or "nil"
            )
        )

        return false
    end

    if dailyPreparationInProgress then
        dbg("prepareRecommendations ignored; already in progress.")
        return false
    end

    if not SLRecommendations then
        if switchToRecommendedSort then SM("Recommendation engine is not loaded.") end
        return false
    end

    local pn = GAMESTATE:GetMasterPlayerNumber()
    if not pn then
        if switchToRecommendedSort then SM("No active player is available for recommendations.") end
        return false
    end

    dailyPreparationInProgress = true

    local ok,
        resultsBySection,
        model,
        err,
        source =
        pcall(
            SLRecommendations.EnsureDailyRecommendations,
            pn,
            {
                count = cfg("WheelResultCount", 100),
                forceRefresh = forceRefresh and true or false,
            }
        )

    dailyPreparationInProgress = false

    if not ok then
        local runtimeError =
            resultsBySection

        dbg(
            "EnsureDailyRecommendations runtime error: " ..
            tostring(runtimeError)
        )

        if switchToRecommendedSort and SM then
            SM(
                "Recommendations error: " ..
                tostring(runtimeError)
            )
        end

        return false
    end

    local forYou = resultsBySection and resultsBySection["For You"] or nil

    dbg(
        "EnsureDailyRecommendations source=" .. tostring(source) ..
        " ForYou=" .. tostring(forYou and #forYou or "nil") ..
        " err=" .. tostring(err)
    )

    if err then
        if switchToRecommendedSort then SM("Recommendations: " .. tostring(err)) end
        return false
    end

    if not forYou or #forYou == 0 then
        if switchToRecommendedSort then SM("No recommendations were available.") end
        return false
    end

    SLRecommendations.SetActive(pn, resultsBySection, model)
    activePlayer = pn

    SONGMAN:SetPreferredSongsFromTable(
        preferredSectionsFromResults(resultsBySection)
    )

    -- Cache hits intentionally skip the full debug rewrite because rebuilding
    -- the expensive model solely for diagnostics defeats the daily cache.
    if cfg("Debug", false)
        and SLRecommendations.WriteDebugFile
        and model
        and not model.fromDailyCache
    then
        SLRecommendations.WriteDebugFile(
            pn,
            forYou,
            model,
            resultsBySection
        )
    end

    if switchToRecommendedSort then
        local ctx = getSortMenuContext()
        if not ctx then
            dbg("prepareRecommendations FAIL: SortMenu context disappeared.")
            return false
        end

        ctx.overlay:queuecommand("DirectInputToEngine")
        ctx.screen:GetMusicWheel():ChangeSort("SortOrder_Preferred")

        MESSAGEMAN:Broadcast("RecommendationsActivated", {
            Player = pn,
            Count = #forYou,
            Source = source,
            Refreshed = forceRefresh and true or false,
        })

        if forceRefresh and SM then SM("Recommendations refreshed.") end
    else
        MESSAGEMAN:Broadcast("RecommendationsPrepared", {
            Player = pn,
            Count = #forYou,
            Source = source,
        })
    end

    dbg(
        "Prepared recommendations P=" .. tostring(pn) ..
        " source=" .. tostring(source) ..
        " ForYouCount=" .. tostring(#forYou)
    )

    return true
end

local function activateRecommendations()
    dbg("activateRecommendations ENTER")
    return prepareRecommendations(false, true)
end

local function refreshRecommendations()
    dbg("refreshRecommendations ENTER")
    return prepareRecommendations(true, true)
end

local function registerCustomFunction()
    local ctx = getSortMenuContext()
    if not ctx then return false end

    if type(ctx.sortmenu.custom_functions) ~= "table" then
        dbg("custom_functions is not a table.")
        return false
    end

    ctx.sortmenu.custom_functions["Recommendations"] =
        activateRecommendations

    ctx.sortmenu.custom_functions["RefreshRecommendations"] =
        refreshRecommendations

    dbg("Registered recommendation custom functions.")
    return true
end

local function applyRecommendedSteps(self)
    if not isRecommendationScreen() then
        return
    end

    if not cfg("AutoSelectRecommendedSteps", true) then
        dbg("AutoSelectRecommendedSteps disabled.")
        return
    end

    local result, localSteps, resolution =
        resolveCurrentRecommendation(true)

    if not result or not localSteps then
        dbg("No selectable recommendation; resolution=" .. tostring(resolution))
        return
    end

    local current = GAMESTATE:GetCurrentSteps(activePlayer)

    dbg("current BEFORE={" .. describeSteps(current) .. "}")

    if current ~= localSteps then
        dbg("SetCurrentSteps via " .. tostring(resolution))
        GAMESTATE:SetCurrentSteps(activePlayer, localSteps)

        MESSAGEMAN:Broadcast(
            "CurrentSteps" .. ToEnumShortString(activePlayer) .. "Changed"
        )
    else
        dbg("Recommended Steps already selected.")
    end

    local after = GAMESTATE:GetCurrentSteps(activePlayer)
    dbg(
        "current AFTER={" .. describeSteps(after) .. "}" ..
        " matched=" .. tostring(after == localSteps)
    )

    if cfg("RecommendationUIDebug", false) then
        self:sleep(0.25):queuecommand("VerifyRecommendedSteps")
    end
end

local function difficultyLabel(steps)
    if not steps then return "" end
    local diff = steps:GetDifficulty()
    return diff and ToEnumShortString(diff) or ""
end

local function recommendationPanelLines(result, localSteps)
    local section = currentPreferredSection() or "Recommended"
    local rank = recommendationRank(result, section)

    local sectionLine =
        section ..
        (rank and ("  #" .. tostring(rank)) or "")

    local steps = localSteps or result.steps
    local stepLine = ""

    if steps then
        local difficulty = difficultyLabel(steps)

        if difficulty ~= "" then
            stepLine = difficulty .. "  "
        end

        stepLine =
            stepLine ..
            tostring(steps:GetMeter())
    end

    local reasons = {}
    local maxReasons = cfg(
        "RecommendationPanelMaxReasons",
        3
    )

    for i = 1, math.min(
        maxReasons,
        #(result.reasons or {})
    ) do
        reasons[#reasons + 1] =
            "- " ..
            result.reasons[i]
    end

    return sectionLine, stepLine, reasons
end

local function hideRecommendationUI(self)
    local panel = self:GetChild("RecommendationPanel")
    local marker = self:GetChild("RecommendedDifficultyMarker")
    local star = self:GetChild("RecommendedBannerStar")

    if panel then panel:visible(false) end
    if marker then marker:visible(false) end
    if star then star:visible(false) end
end

local function refreshRecommendationUI(self)
    if not isRecommendationScreen() then
        hideRecommendationUI(self)
        return
    end

    local panel = self:GetChild("RecommendationPanel")
    local marker = self:GetChild("RecommendedDifficultyMarker")
    local star = self:GetChild("RecommendedBannerStar")
    local song = GAMESTATE:GetCurrentSong()

    if star then
        star:visible(
            activePlayer ~= nil
            and anyRecommendationForSong(song) ~= nil
        )
    end

    local result, localSteps, resolution =
        resolveCurrentRecommendation(false)

    -- The star means "this song is recommended somewhere" and therefore can
    -- remain visible in arbitrary sorts.  The panel + REC difficulty marker
    -- need a specific active recommendation section to disambiguate which
    -- chart/difficulty is intended.
    if not result or not localSteps then
        if panel then panel:visible(false) end
        if marker then marker:visible(false) end
        dbg("Section-specific UI hidden; resolution=" .. tostring(resolution))
        return
    end

    local panelAllowed =
        cfg("ShowRecommendationPanel", cfg("ShowRecommendationHint", true))
        and PANEL.available
        and not (
            cfg("HideRecommendationPanelOnITL", true)
            and isITLOnlineSong()
        )

    if panel and panelAllowed then
        local sectionLine, stepLine, reasons =
            recommendationPanelLines(
                result,
                localSteps
            )

        panel:visible(true)

        panel:GetChild("Section")
            :settext(sectionLine)

        panel:GetChild("Steps")
            :settext(stepLine)

        panel:GetChild("Reason1")
            :settext(reasons[1] or "")

        panel:GetChild("Reason2")
            :settext(reasons[2] or "")

        panel:GetChild("Reason3")
            :settext(reasons[3] or "")
    elseif panel then
        panel:visible(false)
    end

    if marker and cfg("ShowRecommendationDifficultyMarker", true) then
        local row = recommendedDifficultyGridRow(localSteps)

        if row then
            marker:visible(true)
            marker:xy(
                _screen.cx - 26,
                _screen.cy + 67 + (row - 3) * 30
            )

            local label = marker:GetChild("Label")
            if label then
                local isP2 = activePlayer == PLAYER_2
                label:xy(isP2 and 9 or -9, -24)
            end
        else
            marker:visible(false)
        end
    elseif marker then
        marker:visible(false)
    end

    dbg(
        "UI visible section=" .. tostring(currentPreferredSection()) ..
        " rank=" .. tostring(
            recommendationRank(result, currentPreferredSection())
        ) ..
        " via=" .. tostring(resolution)
    )
end

t["ScreenSelectMusic"] = Def.ActorFrame {
    Name="RecommendationsModule",

    InitCommand=function(self)
        self:draworder(10000)
    end,

    ScreenChangedMessageCommand=function(self)
        if not isRecommendationScreen() then
            -- Modules live permanently under ScreenSystemLayer.  Invisible
            -- actors still receive messages, and queued sleep()/queuecommand()
            -- work can otherwise spill into ScreenSelectStyle, EditMenu, etc.
            self:stoptweening()
            hideRecommendationUI(self)

            activePlayer = nil
            installAttempts = 0
            dailyInitAttempts = 0
            dailyPreparationInProgress = false
        end
    end,

    ModuleCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        dbg(
            "ModuleCommand ScreenSelectMusic module=v" ..
            MODULE_VERSION ..
            " script=v" ..
            tostring(
                SLRecommendations
                and SLRecommendations.Version
                or "?"
            )
        )

        activePlayer = nil
        installAttempts = 0
        dailyInitAttempts = 0
        self:queuecommand("TryInit")
    end,

    TryInitCommand=function(self)
        if not isRecommendationScreen() then
            self:stoptweening()
            return
        end

        installAttempts = installAttempts + 1

        local ctx = getSortMenuContext()
        if not ctx then
            if installAttempts <= 40 then
                self:sleep(0.1):queuecommand("TryInit")
            else
                dbg("FAIL: SortMenu context unavailable after retries.")
            end
            return
        end

        local registered = registerCustomFunction()
        local injected = injectRecommendedOption()

        if registered and injected then
            ctx.sortmenu:playcommand("AssessAvailableChoices")
            dbg("Sort integration initialized.")

            self:sleep(0.05)
                :queuecommand("EnsureDailyRecommendations")
        else
            self:sleep(0.1):queuecommand("TryInit")
        end
    end,

    EnsureDailyRecommendationsCommand=function(self)
        if not isRecommendationScreen() then
            self:stoptweening()
            return
        end

        local style =
            GAMESTATE
            and GAMESTATE:GetCurrentStyle()
            or nil

        if not style then
            dailyInitAttempts =
                dailyInitAttempts + 1

            if dailyInitAttempts <= 40 then
                dbg(
                    "CurrentStyle unavailable; retrying daily recommendations (" ..
                    tostring(dailyInitAttempts) ..
                    "/40)."
                )

                self:sleep(0.10)
                    :queuecommand(
                        "EnsureDailyRecommendations"
                    )
            else
                dbg(
                    "Daily recommendations skipped: CurrentStyle never became available."
                )
            end

            return
        end

        dailyInitAttempts = 0

        prepareRecommendations(
            false,
            false
        )

        self:queuecommand(
            "RefreshRecommendationUI"
        )
    end,

    PlayerProfileSetMessageCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        activePlayer = nil
        dailyInitAttempts = 0

        self:sleep(0.10)
            :queuecommand(
                "EnsureDailyRecommendations"
            )
    end,

    RecommendationsPreparedMessageCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        self:queuecommand("RefreshRecommendationUI")
    end,

    RecommendationsActivatedMessageCommand=function(self, params)
        if not isRecommendationScreen() then
            return
        end

        dbg(
            "RecommendationsActivated P=" ..
            tostring(params and params.Player) ..
            " Count=" .. tostring(params and params.Count)
        )

        self:stoptweening()
            :sleep(0.10)
            :queuecommand("ApplyRecommendedSteps")
            :queuecommand("RefreshRecommendationUI")
    end,

    CurrentSongChangedMessageCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        if not activePlayer then return end

        self:stoptweening()
            :sleep(0.08)
            :queuecommand("ApplyRecommendedSteps")
            :queuecommand("RefreshRecommendationUI")
    end,

    CurrentStepsP1ChangedMessageCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        if activePlayer then
            self:queuecommand("RefreshRecommendationUI")
        end
    end,

    CurrentStepsP2ChangedMessageCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        if activePlayer then
            self:queuecommand("RefreshRecommendationUI")
        end
    end,

    SortOrderChangedMessageCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        if activePlayer then
            self:sleep(0.05):queuecommand("RefreshRecommendationUI")
        end
    end,

    SwitchFocusToGroupsMessageCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        hideRecommendationUI(self)
    end,

    SwitchFocusToSongsMessageCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        if activePlayer then
            self:queuecommand("RefreshRecommendationUI")
        end
    end,

    ApplyRecommendedStepsCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        applyRecommendedSteps(self)
    end,

    VerifyRecommendedStepsCommand=function(self)
        if not isRecommendationScreen() then
            return
        end

        local result, localSteps, resolution =
            resolveCurrentRecommendation(false)

        if not result or not localSteps then
            dbg(
                "verify: no recommendation; resolution=" ..
                tostring(resolution)
            )
            return
        end

        local current = GAMESTATE:GetCurrentSteps(activePlayer)

        dbg(
            "VERIFY current={" .. describeSteps(current) ..
            "} target={" .. describeSteps(localSteps) ..
            "} matched=" .. tostring(current == localSteps)
        )
    end,

    RefreshRecommendationUICommand=function(self)
        if not isRecommendationScreen() then
            hideRecommendationUI(self)
            return
        end

        refreshRecommendationUI(self)
    end,

    -- ---------------------------------------------------------------------
    -- Compact recommendation panel: transparent/text-forward on the left.
    -- ---------------------------------------------------------------------
    Def.ActorFrame {
        Name="RecommendationPanel",

        InitCommand=function(self)
            self:xy(PANEL.x, PANEL.y)
                :draworder(10020)
                :visible(false)
        end,

        Def.Quad {
            Name="PanelBorder",
            InitCommand=function(self)
                self:xy(PANEL.width / 2, PANEL.height / 2)
                    :zoomto(PANEL.width, PANEL.height)
                    :diffuse(recommendationAccentColor())
                    :diffusealpha(0.45)
            end,
        },

        Def.Quad {
            Name="PanelBody",
            InitCommand=function(self)
                self:xy(PANEL.width / 2, PANEL.height / 2)
                    :zoomto(PANEL.width - 2, PANEL.height - 2)
                    :diffuse(Color.Black)
                    :diffusealpha(0.62)
            end,
        },

        Def.Quad {
            Name="AccentLine",
            InitCommand=function(self)
                self:xy(3, PANEL.height / 2)
                    :zoomto(3, PANEL.height - 6)
                    :diffuse(recommendationAccentColor())
                    :diffusealpha(0.95)
            end,
        },

        Def.BitmapText {
            Name="Header",
            Font="Common Bold",
            Text="RECOMMENDED",
            InitCommand=function(self)
                self:horizalign(left)
                    :xy(10, 10)
                    :zoom(0.26)
                    :maxwidth((PANEL.width - 18) / 0.26)
                    :diffuse(recommendationAccentColor())
                    :strokecolor(Color.Black)
            end,
        },

        Def.BitmapText {
            Name="Section",
            Font="Common Bold",
            InitCommand=function(self)
                self:horizalign(left)
                    :xy(10, 29)
                    :zoom(0.30)
                    :maxwidth((PANEL.width - 18) / 0.30)
                    :diffuse(Color.White)
                    :strokecolor(Color.Black)
            end,
        },

        -- Difficulty appears exactly once in this panel.
        Def.BitmapText {
            Name="Steps",
            Font="Common Bold",
            InitCommand=function(self)
                self:horizalign(left)
                    :xy(10, 50)
                    :zoom(0.30)
                    :maxwidth((PANEL.width - 18) / 0.30)
                    :diffuse(recommendationAccentColor())
                    :strokecolor(Color.Black)
            end,
        },

        -- Reasons are the primary purpose of this panel.  Use the same bold
        -- font family as the readable header/section lines, keep a fixed zoom,
        -- and wrap rather than ever shrinking text with maxwidth().
        Def.BitmapText {
            Name="Reason1",
            Font="Common Normal",
            InitCommand=function(self)
                self:horizalign(left)
                    :vertalign(top)
                    :xy(10, 78)
                    :zoom(0.54)
                    :wrapwidthpixels(
                        (PANEL.width - 18) / 0.32
                    )
                    :vertspacing(0)
                    :diffuse(
                        0.96,
                        0.96,
                        0.96,
                        1
                    )
                    :strokecolor(Color.Black)
            end,
        },

        Def.BitmapText {
            Name="Reason2",
            Font="Common Normal",
            InitCommand=function(self)
                self:horizalign(left)
                    :vertalign(top)
                    :xy(10, 121)
                    :zoom(0.54)
                    :wrapwidthpixels(
                        (PANEL.width - 18) / 0.32
                    )
                    :vertspacing(0)
                    :diffuse(
                        0.90,
                        0.90,
                        0.90,
                        1
                    )
                    :strokecolor(Color.Black)
            end,
        },

        Def.BitmapText {
            Name="Reason3",
            Font="Common Normal",
            InitCommand=function(self)
                self:horizalign(left)
                    :vertalign(top)
                    :xy(10, 164)
                    :zoom(0.54)
                    :wrapwidthpixels(
                        (PANEL.width - 18) / 0.32
                    )
                    :vertspacing(0)
                    :diffuse(
                        0.84,
                        0.84,
                        0.84,
                        1
                    )
                    :strokecolor(Color.Black)
            end,
        },
    },

    -- Gold star on the selected song banner if this song appears in ANY active
    -- recommendation section.  The exact-difficulty REC marker remains
    -- section-specific because different sections can recommend different
    -- charts of the same song.
    Def.ActorFrame {
        Name="RecommendedBannerStar",
        InitCommand=function(self)
            self:xy(BANNER_STAR.x, BANNER_STAR.y)
                :draworder(10025)
                :visible(false)
        end,

        Def.ActorMultiVertex {
            InitCommand=function(self)
                self:SetDrawState({Mode="DrawMode_Triangles"})
                    :SetVertices(starVertices(12, 5.5))
                    :xy(1, 1)
                    :diffuse(Color.Black)
                    :diffusealpha(0.75)
            end,
        },

        Def.ActorMultiVertex {
            InitCommand=function(self)
                self:SetDrawState({Mode="DrawMode_Triangles"})
                    :SetVertices(starVertices(10, 4.5))
                    :diffuse(recommendationAccentColor())
            end,
        },
    },

    -- ---------------------------------------------------------------------
    -- Recommended difficulty marker.
    --
    -- Simply Love's normal grid uses 28px blocks spaced every 30px at
    -- (_screen.cx-26, _screen.cy+67).  Draw a small outline and REC tag over
    -- the row containing the recommended Steps.  This remains visible when
    -- the user manually changes difficulty, making the intended chart clear.
    -- ---------------------------------------------------------------------
    Def.ActorFrame {
        Name="RecommendedDifficultyMarker",

        InitCommand=function(self)
            self:draworder(10030)
                :visible(false)
        end,

        Def.Quad {
            InitCommand=function(self)
                self:zoomto(30, 30)
                    :diffuse(recommendationAccentColor())
                    :diffusealpha(0.10)
            end,
        },

        Def.Quad {
            InitCommand=function(self)
                self:xy(0, -16)
                    :zoomto(34, 2)
                    :diffuse(recommendationAccentColor())
            end,
        },

        Def.Quad {
            InitCommand=function(self)
                self:xy(0, 16)
                    :zoomto(34, 2)
                    :diffuse(recommendationAccentColor())
            end,
        },

        Def.Quad {
            InitCommand=function(self)
                self:xy(-16, 0)
                    :zoomto(2, 34)
                    :diffuse(recommendationAccentColor())
            end,
        },

        Def.Quad {
            InitCommand=function(self)
                self:xy(16, 0)
                    :zoomto(2, 34)
                    :diffuse(recommendationAccentColor())
            end,
        },

        Def.BitmapText {
            Name="Label",
            Font="Common Bold",
            Text="REC",
            InitCommand=function(self)
                self:xy(-9, -24)
                    :zoom(0.22)
                    :diffuse(recommendationAccentColor())
                    :strokecolor(Color.Black)
            end,
        },
    },
}

return t
