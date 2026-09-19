-- ITGmania / Simply Love Recommendations module
-- v14
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
local MODULE_VERSION = "20"

local installAttempts = 0
local activePlayer = nil

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

local function anyPersistentHumanProfile()
    if GAMESTATE:IsCourseMode() then return false end

    for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
        if PROFILEMAN:IsPersistentProfile(pn) then
            return true
        end
    end

    return false
end

local function getSortMenuContext()
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

local function recommendedOptionExists(sortmenu)
    for _, option in ipairs(sortmenu.wheel_options or {}) do
        if type(option) == "table"
            and type(option[1]) == "table"
            and option[1][2] == "CategoryProfile"
            and type(option[2]) == "table"
        then
            for _, suboption in ipairs(option[2]) do
                if type(suboption) == "table"
                    and type(suboption[1]) == "table"
                    and suboption[1][2] == "Recommendations"
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

    if recommendedOptionExists(ctx.sortmenu) then
        dbg("SortMenu option already present.")
        return true
    end

    for _, option in ipairs(ctx.sortmenu.wheel_options or {}) do
        if type(option) == "table"
            and type(option[1]) == "table"
            and option[1][2] == "CategoryProfile"
            and type(option[2]) == "table"
        then
            table.insert(option[2], {
                {"For You", "Recommendations"},
                anyPersistentHumanProfile,
            })

            dbg("Inserted Recommendations under CategoryProfile.")
            return true
        end
    end

    table.insert(ctx.sortmenu.wheel_options, {
        {"For You", "Recommendations"},
        anyPersistentHumanProfile,
    })

    dbg("CategoryProfile not found; inserted top-level fallback.")
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

local function activateRecommendations()
    dbg("activateRecommendations ENTER")

    if not SLRecommendations then
        SM("Recommendation engine is not loaded.")
        return
    end

    local pn = GAMESTATE:GetMasterPlayerNumber()
    if not pn then
        SM("No active player is available for recommendations.")
        return
    end

    local count = cfg("WheelResultCount", 100)

    local resultsBySection, model, err =
        SLRecommendations.GenerateModes(
            pn,
            { count = count }
        )

    local forYou =
        resultsBySection
        and resultsBySection["For You"]
        or nil

    dbg(
        "GenerateModes -> For You=" ..
        tostring(forYou and #forYou or "nil") ..
        " err=" .. tostring(err)
    )

    if err then
        SM("Recommendations: " .. tostring(err))
        return
    end

    if not forYou or #forYou == 0 then
        SM("No recommendations were available.")
        return
    end

    SLRecommendations.SetActive(
        pn,
        resultsBySection,
        model
    )

    activePlayer = pn

    if cfg("Debug", false)
        and SLRecommendations.WriteDebugFile
    then
        SLRecommendations.WriteDebugFile(
            pn,
            forYou,
            model,
            resultsBySection
        )
    end

    local preferredSections = {}

    for section, results in pairs(resultsBySection) do
        local songs = {}

        for _, result in ipairs(results) do
            songs[#songs + 1] = result.song
        end

        preferredSections[section] = songs
    end

    SONGMAN:SetPreferredSongsFromTable(
        preferredSections
    )

    local ctx = getSortMenuContext()
    if not ctx then
        dbg("activateRecommendations FAIL: SortMenu context disappeared.")
        return
    end

    ctx.overlay:queuecommand("DirectInputToEngine")
    ctx.screen:GetMusicWheel():ChangeSort("SortOrder_Preferred")

    dbg(
        "Activated P=" .. tostring(pn) ..
        " sections=" .. tostring(model and model.modeOrder and #model.modeOrder or 0) ..
        " ForYouCount=" .. tostring(#forYou) ..
        " first=" .. tostring(forYou[1].song:GetDisplayFullTitle()) ..
        " firstDir=" .. tostring(forYou[1].song:GetSongDir()) ..
        " firstTarget={" .. describeSteps(forYou[1].steps) .. "}"
    )

    MESSAGEMAN:Broadcast("RecommendationsActivated", {
        Player = pn,
        Count = #forYou,
    })
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

    dbg("Registered custom function.")
    return true
end

local function applyRecommendedSteps(self)
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

local function hintText(result, localSteps)
    local section = currentPreferredSection() or "Recommended"
    local rank = recommendationRank(result, section)

    local title =
        section ..
        (rank and (" #" .. tostring(rank)) or "")

    local steps = localSteps or result.steps
    local detail = difficultyLabel(steps)

    if steps then
        if detail ~= "" then detail = detail .. " " end
        detail = detail .. tostring(steps:GetMeter())

        local credit = steps:GetAuthorCredit() or ""
        if credit ~= "" then
            detail = detail .. " • " .. credit
        end
    end

    local reasons = {}
    for i = 1, math.min(3, #(result.reasons or {})) do
        reasons[#reasons + 1] = result.reasons[i]
    end

    if #reasons > 0 then
        detail = detail .. " — " .. table.concat(reasons, " • ")
    end

    return title, detail
end

t["ScreenSelectMusic"] = Def.ActorFrame {
    Name="RecommendationsModule",

    -- InitCommand is normal Actor initialization and is valid for modules.
    -- ModuleCommand is the screen-entry lifecycle hook supplied by Simply Love.
    InitCommand=function(self)
        self:draworder(10000)
    end,

    ModuleCommand=function(self)
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
        self:queuecommand("TryInit")
    end,

    TryInitCommand=function(self)
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
        else
            self:sleep(0.1):queuecommand("TryInit")
        end
    end,

    RecommendationsActivatedMessageCommand=function(self, params)
        dbg(
            "RecommendationsActivated P=" ..
            tostring(params and params.Player) ..
            " Count=" .. tostring(params and params.Count)
        )

        self:stoptweening()
            :sleep(0.10)
            :queuecommand("ApplyRecommendedSteps")
            :queuecommand("RefreshRecommendationHint")
    end,

    CurrentSongChangedMessageCommand=function(self)
        if not activePlayer then return end

        dbg(
            "CurrentSongChanged -> " ..
            tostring(
                GAMESTATE:GetCurrentSong()
                and GAMESTATE:GetCurrentSong():GetDisplayFullTitle()
                or "nil"
            )
        )

        self:stoptweening()
            :sleep(0.10)
            :queuecommand("ApplyRecommendedSteps")
            :queuecommand("RefreshRecommendationHint")
    end,

    ApplyRecommendedStepsCommand=function(self)
        applyRecommendedSteps(self)
    end,

    VerifyRecommendedStepsCommand=function(self)
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

    RefreshRecommendationHintCommand=function(self)
        local box = self:GetChild("RecommendationHintBox")
        local title = self:GetChild("RecommendationHintTitle")
        local detail = self:GetChild("RecommendationHintDetail")

        if not cfg("ShowRecommendationHint", true) then
            box:visible(false)
            title:visible(false)
            detail:visible(false)
            return
        end

        local result, localSteps, resolution =
            resolveCurrentRecommendation(false)

        if not result or not localSteps then
            box:visible(false)
            title:visible(false)
            detail:visible(false)

            dbg("Hint hidden; resolution=" .. tostring(resolution))
            return
        end

        local titleText, detailText =
            hintText(result, localSteps)

        box:visible(true)
        title:visible(true):settext(titleText)
        detail:visible(true):settext(detailText)

        dbg(
            "Hint visible section=" ..
            tostring(currentPreferredSection()) ..
            " rank=" ..
            tostring(
                recommendationRank(
                    result,
                    currentPreferredSection()
                )
            ) ..
            " via=" .. tostring(resolution)
        )
    end,

    -- Visual children use ordinary InitCommand.  Existing Simply Love modules
    -- do the same; only the root screen-specific module actor needs the
    -- ModuleCommand lifecycle hook.
    Def.Quad {
        Name="RecommendationHintBox",
        InitCommand=function(self)
            self:xy(_screen.cx, 100)
                :zoomto(math.min(760, _screen.w - 40), 48)
                :diffuse(Color.Black)
                :diffusealpha(0.90)
                :draworder(10000)
                :visible(false)
        end,
    },

    Def.BitmapText {
        Name="RecommendationHintTitle",
        Font="Common Bold",
        InitCommand=function(self)
            self:xy(_screen.cx, 90)
                :zoom(0.45)
                :diffuse(Color.White)
                :draworder(10001)
                :visible(false)
        end,
    },

    Def.BitmapText {
        Name="RecommendationHintDetail",
        Font="Common Normal",
        InitCommand=function(self)
            self:xy(_screen.cx, 111)
                :zoom(0.34)
                :maxwidth((math.min(760, _screen.w - 40) - 20) / 0.34)
                :diffuse(0.90, 0.90, 0.90, 1)
                :draworder(10001)
                :visible(false)
        end,
    },
}

return t
