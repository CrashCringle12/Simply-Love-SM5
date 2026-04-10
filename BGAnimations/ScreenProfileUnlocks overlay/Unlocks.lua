local args = ...
local player = args.Player
local profile_data = args.ProfileData
local guest_data = args.GuestData
local avatars = args.Avatars
local pn = ToEnumShortString(player)
local frame = {w = 225, h = 368, border = 6}
local downloadStatus

-- -----------------------------------------------------------------------
-- JSON reading utility

local ReadJSONFile = function(path)
    local f = RageFileUtil.CreateRageFile()
    local data = nil
    if f:Open(path, 1) then
        data = JsonDecode(f:Read())
        f:Close()
    end
    f:destroy()
    return data
end

-- -----------------------------------------------------------------------
-- Load unlock data: try profile's ITL-unlocks.json, fallback to theme's unlocks.json

local LoadUnlockData = function()
    local profile = PROFILEMAN:GetProfile(player)
    if profile then
        local slot = player == PLAYER_1 and "ProfileSlot_Player1" or "ProfileSlot_Player2"
        local dir = PROFILEMAN:GetProfileDir(slot)
        if dir and dir ~= "" then
            local data = ReadJSONFile(dir .. "ITL-unlocks.json")
            if data then return data end
        end
    end
    local fallback = THEME:GetCurrentThemeDirectory() .. "BGAnimations/ScreenProfileAchievements overlay/unlocks.json"
    return ReadJSONFile(fallback)
end

-- -----------------------------------------------------------------------
-- Build chains from unlock JSON data

local BuildChains = function(jsonData)
    if not jsonData or not jsonData.data or not jsonData.data.nodes then return {} end

    local nodeMap = {}
    for _, node in ipairs(jsonData.data.nodes) do
        nodeMap[tostring(node.id)] = node
    end

    -- Find roots (no incoming edges)
    local hasParent = {}
    if jsonData.data.edges then
        for _, edge in ipairs(jsonData.data.edges) do
            hasParent[tostring(edge.to)] = true
        end
    end

    local roots = {}
    for _, node in ipairs(jsonData.data.nodes) do
        if not hasParent[tostring(node.id)] then
            roots[#roots + 1] = node
        end
    end

    table.sort(roots, function(a, b) return (a.title or "") < (b.title or "") end)

    -- Build chains via DFS from each root (allow cross-chain duplicates)
    local chains = {}
    for _, root in ipairs(roots) do
        local chainNodes = {}
        local chainVisited = {}
        local function dfs(nodeId, depth)
            local key = tostring(nodeId)
            if chainVisited[key] then return end
            chainVisited[key] = true
            local node = nodeMap[key]
            if not node then return end
            chainNodes[#chainNodes + 1] = {node = node, depth = depth}
            if node.data and node.data.childIds then
                for _, childId in ipairs(node.data.childIds) do
                    dfs(childId, depth + 1)
                end
            end
        end
        dfs(root.id, 0)
        if #chainNodes > 0 then
            chains[#chains + 1] = {
                name = root.title or "???",
                nodes = chainNodes,
            }
        end
    end

    return chains
end

-- -----------------------------------------------------------------------

local unlockData = LoadUnlockData()
local chains = BuildChains(unlockData)

if #chains == 0 then
    chains = {{name = "No Data", nodes = {}}}
end

-- Navigation state
local nav = {
    chainIndex = 1,
    nodeIndex = 1,
    scrollOffset = 0,
    chains = chains,
}

-- Store nav on SL.Accolades.Unlocks so Input.lua can access it
SL.Accolades.Unlocks.Nav[pn] = nav

-- -----------------------------------------------------------------------
-- Helpers

local maxVisibleNodes = 8

local StatusColor = function(status)
    if status == "complete" then return color("#4CAF50") end
    if status == "in-progress" then return color("#FFC107") end
    return color("#757575")
end

local StatusIcon = function(status)
    if status == "complete" then return "✅ " end
    if status == "in-progress" then return "⚒ " end
    return "❓ "
end

local CondStatusIcon = function(status)
    if status == "complete" then return "  ✅ " end
    return "  ✗ "
end

local CountChainComplete = function(chain)
    if not chain or not chain.nodes then return 0, 0 end
    local c = 0
    for _, entry in ipairs(chain.nodes) do
        if entry.node.status == "complete" then c = c + 1 end
    end
    return c, #chain.nodes
end

local CountTotalComplete = function()
    local uniqueComplete, uniqueTotal = 0, 0
    local seen = {}
    for _, chain in ipairs(chains) do
        for _, entry in ipairs(chain.nodes) do
            local id = tostring(entry.node.id)
            if not seen[id] then
                seen[id] = true
                uniqueTotal = uniqueTotal + 1
                if entry.node.status == "complete" then
                    uniqueComplete = uniqueComplete + 1
                end
            end
        end
    end
    return uniqueComplete, uniqueTotal
end

-- -----------------------------------------------------------------------
-- Frame backgrounds (same as achievements)

local FrameBackground2 = function(pad, c, plyr, w, h)
    w = w or frame.w
    return Def.ActorFrame {
        OnCommand = function(self)
            self:runcommandsonleaves(function(leaf) leaf:smooth(0.3):cropbottom(0) end)
            self:x(pad):y(60)
        end,
        OffCommand = function(self)
            if not GAMESTATE:IsSideJoined(plyr) then
                self:runcommandsonleaves(function(leaf) leaf:accelerate(0.25):cropbottom(1) end)
            end
        end,
        Def.Quad {
            InitCommand = function(self)
                self:horizalign(left):vertalign(top):setsize(540, 120):xy(-self:GetWidth()/2, 100):MaskSource()
            end
        },
        Def.Quad {
            InitCommand = function(self)
                self:cropbottom(1):zoomto(w + frame.border, h + frame.border)
                if ThemePrefs.Get("RainbowMode") then self:diffuse(Color.Black) end
            end
        },
        Def.Quad {
            InitCommand = function(self)
                self:cropbottom(1):zoomto(w, h):diffuse(c):diffusetopedge(LightenColor(c))
            end
        }
    }
end

local FrameBackground3 = function(pad, c, plyr, w, h)
    w = w or frame.w
    return Def.ActorFrame {
        OnCommand = function(self)
            self:runcommandsonleaves(function(leaf) leaf:smooth(0.3):cropbottom(0) end)
            self:x(pad):y(-108)
        end,
        OffCommand = function(self)
            if not GAMESTATE:IsSideJoined(plyr) then
                self:runcommandsonleaves(function(leaf) leaf:accelerate(0.25):cropbottom(1) end)
            end
        end,
        Def.Quad {
            InitCommand = function(self)
                self:horizalign(left):vertalign(top):setsize(540, 120):xy(-self:GetWidth()/2, 100):MaskSource()
            end
        },
        Def.Quad {
            InitCommand = function(self)
                self:cropbottom(1):zoomto(w + frame.border, h + frame.border)
                if ThemePrefs.Get("RainbowMode") then self:diffuse(Color.Black) end
            end
        },
        Def.Quad {
            InitCommand = function(self)
                self:cropbottom(1):zoomto(w, h):diffuse(c):diffusetopedge(LightenColor(c))
            end
        }
    }
end

-- -----------------------------------------------------------------------
-- Find initial profile data

local initial_data = guest_data
local pos = 0
for profile in ivalues(profile_data) do
    if profile.guid == PROFILEMAN:GetProfile(player):GetGUID() then
        pos = profile.index
        break
    end
end
initial_data = pos == 0 and guest_data or profile_data[pos]

local avatar_dim = 85

-- -----------------------------------------------------------------------
-- Build the main actor frame

local t = Def.ActorFrame {
    Name = "UnlockFrame",
    InitCommand = function(self)
        self:queuecommand("Prime")
    end,
    PrimeCommand = function(self)
        self:playcommand("Set", {
            chainIndex = nav.chainIndex,
            nodeIndex = nav.nodeIndex,
            displayname = initial_data and initial_data.displayname or "",
            index = initial_data and initial_data.index or 0,
        })
    end,
    SetCommand = function(self, params)
        if params then
            nav.chainIndex = params.chainIndex or nav.chainIndex
            nav.nodeIndex = params.nodeIndex or nav.nodeIndex
        end
        -- Clamp
        if nav.chainIndex < 1 then nav.chainIndex = 1 end
        if nav.chainIndex > #chains then nav.chainIndex = #chains end
        local chain = chains[nav.chainIndex]
        if chain and #chain.nodes > 0 then
            if nav.nodeIndex < 1 then nav.nodeIndex = 1 end
            if nav.nodeIndex > #chain.nodes then nav.nodeIndex = #chain.nodes end
        else
            nav.nodeIndex = 1
        end
        -- Adjust scroll
        if nav.nodeIndex > nav.scrollOffset + maxVisibleNodes then
            nav.scrollOffset = nav.nodeIndex - maxVisibleNodes
        elseif nav.nodeIndex <= nav.scrollOffset then
            nav.scrollOffset = nav.nodeIndex - 1
        end

        MESSAGEMAN:Broadcast("UnlockUpdate", {
            Player = player,
            chainIndex = nav.chainIndex,
            nodeIndex = nav.nodeIndex,
            scrollOffset = nav.scrollOffset,
            displayname = params and params.displayname or (initial_data and initial_data.displayname or ""),
            index = params and params.index or (initial_data and initial_data.index or 0),
            downloadStatus = params and params.downloadStatus or nil,
        })
    end,
}

-- Inner ActorFrame for visual layout
local inner = Def.ActorFrame {
    InitCommand = function(self)
        self:xy(_screen.cx, _screen.cy + 10):zoom(0):diffusealpha(0)
        self:visible(true):smooth(0.3):diffusealpha(1):zoom(1)
    end,
    HideCommand = function(self)
        self:smooth(0.3):diffusealpha(0):zoom(0)
    end,

    -- Backgrounds
    FrameBackground3(0, color("#575867"), player, frame.w * 3.2, frame.h * 0.3),
    FrameBackground2(0, color("#f5f5f5"), player, frame.w * 3.2, frame.h * 0.59),

    -- Header: "Unlocks" label
    LoadFont("Common Normal") .. {
        Text = "Unlocks",
        InitCommand = function(self)
            self:valign(0):horizalign(left):zoom(1):diffusealpha(0.9):xy(-330, -190):diffuse(color("#FFFFFF"))
        end,
    },

    -- Header: Player's Unlock Chains
    LoadFont("Common Header") .. {
        Text = "Unlock Chains",
        InitCommand = function(self)
            self:valign(0):horizalign(left):zoom(0.4):diffusealpha(0.9):xy(-332, -148):diffuse(color("#FFFFFF"))
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            local name = params.displayname or ""
            if name ~= "" then
                self:settext(name .. "'s Unlock Chains")
            else
                self:settext("Unlock Chains")
            end
        end,
    },

    -- Chain name (large)
    LoadFont("Wendy/_wendy small") .. {
        Text = "",
        InitCommand = function(self)
            self:valign(0):horizalign(left):zoom(0.3):diffusealpha(0.9):xy(-330, -120):diffuse(color("#c7cbd9"))
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            local chain = chains[params.chainIndex]
            if chain then
                self:settext("Chain: " .. chain.name)
            else
                self:settext("No chains")
            end
        end,
    },

    -- Chain progress text
    LoadFont("Common Normal") .. {
        Text = "",
        InitCommand = function(self)
            self:valign(0):horizalign(left):zoom(0.8):diffusealpha(0.9):xy(-330, -100):diffuse(color("#c7cbd9"))
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            local chain = chains[params.chainIndex]
            if chain then
                local c, tot = CountChainComplete(chain)
                self:settext(c .. " of " .. tot .. " nodes complete in this chain")
            else
                self:settext("")
            end
        end,
    },

    -- Chain counter (top right)
    LoadFont("Common Normal") .. {
        Text = "",
        InitCommand = function(self)
            self:valign(0):horizalign(right):zoom(1):diffusealpha(0.9):xy(350, -150):diffuse(color("#FFFFFF"))
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            self:settext("Chain " .. params.chainIndex .. " of " .. #chains)
        end,
    },

    -- Node status (top right)
    LoadFont("Wendy/_wendy small") .. {
        Text = "",
        InitCommand = function(self)
            self:valign(0):horizalign(right):zoom(0.25):diffusealpha(0.9):xy(350, -115):diffuse(color("#FFFFFF"))
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            local chain = chains[params.chainIndex]
            if chain and chain.nodes[params.nodeIndex] then
                local node = chain.nodes[params.nodeIndex].node
                local status = node.status or "not-started"
                if status == "complete" then
                    self:settext("Complete"):diffuse(color("#4CAF50"))
                elseif status == "in-progress" then
                    self:settext("In Progress"):diffuse(color("#FFC107"))
                else
                    self:settext("Not Started"):diffuse(color("#9E9E9E"))
                end
            else
                self:settext("")
            end
        end,
    },

    -- Download status
    LoadFont("Common Normal") .. {
        Text = "",
        Name = "DownloadStatus",
        InitCommand = function(self)
            self:valign(0):horizalign(right):zoom(0.9):diffusealpha(0.9):xy(350, -90):diffuse(color("#FFFFFF"))
            downloadStatus = self
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            local chain = chains[params.chainIndex]
            if not chain or not chain.nodes[params.nodeIndex] then
                self:settext("")
                return
            end
            local node = chain.nodes[params.nodeIndex].node
            local dirs = node.data and node.data.chartsSongDirs
            local link = node.data and node.data.downloadLink

            -- Check if all songs are already downloaded
            local allDownloaded = false
            if dirs and #dirs > 0 then
                allDownloaded = true
                for _, dir in ipairs(dirs) do
                    if not SONGMAN:FindSong(dir) then
                        allDownloaded = false
                        break
                    end
                end
            end
            local nodeId = tostring(node.id or node.data and node.data.id or "")

            -- If a download was just triggered, show downloading state
            if params.downloadStatus == "downloading" then
                self:settext("Downloading..."):diffuse(color("#FF9800"))
                return
            end

            if allDownloaded or SL.Accolades.Unlocks.Downloaded[nodeId] then
                self:settext("Load New Songs"):diffuse(color("#4CAF50"))
            elseif link and link ~= "" then
                self:settext("&START; to DOWNLOAD"):diffuse(color("#FFC107"))
            else
                self:settext("Unavailable"):diffuse(color("#9E9E9E"))
            end
        end,
    },

    -- DateTime
    LoadFont("Common Normal") .. {
        Name = "DateTime",
        InitCommand = function(self)
            self:xy(_screen.cx - 63, -180):horizalign(right):zoom(1)
        end,
        OnCommand = function(self)
            self:diffuse(Color.White):playcommand("Refresh")
        end,
        RefreshCommand = function(self)
            local DateFormat = "%04d/%02d/%02d %02d:%02d"
            self:settext(DateFormat:format(Year(), MonthOfYear() + 1, DayOfMonth(), Hour(), Minute()))
        end
    },

    -- Navigation arrows
    Def.Sprite {
        Texture = "../ScreenProfileAchievements overlay/arrow",
        InitCommand = function(self)
            self:xy(300, 155):zoom(0.9):diffuse(color("#c7cbd9")):rotationz(-90)
        end
    },
    Def.Sprite {
        Texture = "../ScreenProfileAchievements overlay/arrow",
        InitCommand = function(self)
            self:xy(325, 155):zoom(0.9):diffuse(color("#c7cbd9")):rotationz(90)
        end
    },

    -- Bottom summary
    LoadFont("Common Normal") .. {
        Text = "",
        InitCommand = function(self)
            self:valign(0):horizalign(left):zoom(0.9):diffusealpha(0.9):xy(-332, 148):diffuse(color("#575867"))
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            local c, tot = CountTotalComplete()
            self:settext(c .. " of " .. tot .. " unlock nodes complete.")
        end,
    },
}

-- -----------------------------------------------------------------------
-- LEFT PANEL: Chain node list (scrollable, up to maxVisibleNodes visible)

local nodeListBaseX = -330
local nodeListBaseY = -25
local nodeListLineH = 22

for i = 1, maxVisibleNodes do
    inner[#inner + 1] = Def.ActorFrame {
        -- Background highlight quad
        Def.Quad {
            InitCommand = function(self)
                self:horizalign(left):vertalign(0):zoomto(220, nodeListLineH - 2)
                self:xy(nodeListBaseX, -4 + nodeListBaseY + (i - 1) * nodeListLineH)
                self:diffuse(0, 0, 0, 0)
            end,
            UnlockUpdateMessageCommand = function(self, params)
                if params.Player ~= player then return end
                local visIndex = i + params.scrollOffset
                if visIndex == params.nodeIndex then
                    self:diffuse(color("#3F51B5aa"))
                else
                    self:diffuse(0, 0, 0, 0)
                end
            end,
        },
        -- Node text
        LoadFont("Common Normal") .. {
            Text = "",
            InitCommand = function(self)
                self:valign(0):horizalign(left):zoom(0.7)
                self:xy(nodeListBaseX + 2, nodeListBaseY + (i - 1) * nodeListLineH)
                self:maxwidth(290)
            end,
            UnlockUpdateMessageCommand = function(self, params)
                if params.Player ~= player then return end
                local chain = chains[params.chainIndex]
                local visIndex = i + params.scrollOffset
                if chain and chain.nodes[visIndex] then
                    local entry = chain.nodes[visIndex]
                    local indent = string.rep("  ", entry.depth)
                    local icon = StatusIcon(entry.node.status)
                    self:settext(indent .. icon .. (entry.node.title or "???"))
                    if visIndex == params.nodeIndex then
                        self:diffuse(color("#FFFFFF"))
                    else
                        self:diffuse(StatusColor(entry.node.status))
                    end
                    self:visible(true)
                else
                    self:settext("")
                    self:visible(false)
                end
            end,
        },
    }
end

-- -----------------------------------------------------------------------
-- Vertical separator line between panels

inner[#inner + 1] = Def.Quad {
    InitCommand = function(self)
        self:zoomto(2, 175):xy(-100, 60):diffuse(color("#CCCCCC")):diffusealpha(0.5)
    end,
}

-- -----------------------------------------------------------------------
-- RIGHT PANEL: Node detail

local detailX = -70
local detailBaseY = -30

-- Node title
inner[#inner + 1] = LoadFont("Wendy/_wendy small") .. {
    Text = "",
    InitCommand = function(self)
        self:valign(0):horizalign(left):zoom(0.28):xy(detailX, detailBaseY):diffuse(color("#333333"))
        self:maxwidth(1400)
    end,
    UnlockUpdateMessageCommand = function(self, params)
        if params.Player ~= player then return end
        local chain = chains[params.chainIndex]
        if chain and chain.nodes[params.nodeIndex] then
            local node = chain.nodes[params.nodeIndex].node
            self:settext(node.title or "???")
            self:diffuse(StatusColor(node.status))
        else
            self:settext("")
        end
    end,
}

-- Node status / date
inner[#inner + 1] = LoadFont("Common Normal") .. {
    Text = "",
    InitCommand = function(self)
        self:valign(0):horizalign(left):zoom(0.7):xy(detailX, detailBaseY + 22):diffuse(color("#666666"))
    end,
    UnlockUpdateMessageCommand = function(self, params)
        if params.Player ~= player then return end
        local chain = chains[params.chainIndex]
        if chain and chain.nodes[params.nodeIndex] then
            local node = chain.nodes[params.nodeIndex].node
            local status = node.status or "not-started"
            if status == "complete" and node.data and node.data.dateCompleted then
                local date = tostring(node.data.dateCompleted):sub(1, 10)
                self:settext("Completed: " .. date):diffuse(color("#4CAF50"))
            elseif status == "complete" then
                self:settext("Complete"):diffuse(color("#4CAF50"))
            elseif status == "in-progress" then
                self:settext("In Progress"):diffuse(color("#FFC107"))
            else
                self:settext("Not Started"):diffuse(color("#757575"))
            end
        else
            self:settext("")
        end
    end,
}

-- "Requirements:" header
inner[#inner + 1] = LoadFont("Common Normal") .. {
    Text = "Requirements:",
    InitCommand = function(self)
        self:valign(0):horizalign(left):zoom(0.7):xy(detailX, detailBaseY + 40):diffuse(color("#333333"))
    end,
    UnlockUpdateMessageCommand = function(self, params)
        if params.Player ~= player then return end
        local chain = chains[params.chainIndex]
        self:visible(chain and chain.nodes[params.nodeIndex] ~= nil)
    end,
}

-- Requirement lines (up to 5)
local maxReqLines = 5
local reqStartY = detailBaseY + 55

for i = 1, maxReqLines do
    inner[#inner + 1] = LoadFont("Common Normal") .. {
        Text = "",
        InitCommand = function(self)
            self:valign(0):horizalign(left):zoom(0.55):xy(detailX, reqStartY + (i - 1) * 14)
            self:maxwidth(700)
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            local chain = chains[params.chainIndex]
            if chain and chain.nodes[params.nodeIndex] then
                local node = chain.nodes[params.nodeIndex].node
                local conditions = node.conditions
                if conditions and conditions[i] then
                    local cond = conditions[i]
                    local icon = CondStatusIcon(cond.status)
                    self:settext(icon .. cond.text)
                    if cond.status == "complete" then
                        self:diffuse(color("#4CAF50"))
                    else
                        self:diffuse(color("#E53935"))
                    end
                    self:visible(true)
                else
                    self:settext("")
                    self:visible(false)
                end
            else
                self:settext("")
                self:visible(false)
            end
        end,
    }
end

-- "Songs Unlocked:" header
local unlocksHeaderY = reqStartY + maxReqLines * 14 + 5

inner[#inner + 1] = LoadFont("Common Normal") .. {
    Text = "Songs Unlocked:",
    InitCommand = function(self)
        self:valign(0):horizalign(left):zoom(0.7):xy(detailX, unlocksHeaderY):diffuse(color("#333333"))
    end,
    UnlockUpdateMessageCommand = function(self, params)
        if params.Player ~= player then return end
        local chain = chains[params.chainIndex]
        if chain and chain.nodes[params.nodeIndex] then
            local node = chain.nodes[params.nodeIndex].node
            local hasUnlocks = (type(node.unlocks) == "table" and #node.unlocks > 0)
            self:visible(hasUnlocks)
        else
            self:visible(false)
        end
    end,
}

-- Unlock lines (up to 4)
local maxUnlockLines = 4
local unlockStartY = unlocksHeaderY + 15

for i = 1, maxUnlockLines do
    inner[#inner + 1] = LoadFont("Common Normal") .. {
        Text = "",
        InitCommand = function(self)
            self:valign(0):horizalign(left):zoom(0.55):xy(detailX, unlockStartY + (i - 1) * 14)
            self:maxwidth(700)
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            local chain = chains[params.chainIndex]
            if chain and chain.nodes[params.nodeIndex] then
                local node = chain.nodes[params.nodeIndex].node
                if node.unlocks and node.unlocks[i] then
                    local unlock = node.unlocks[i]
                    local icon = unlock.status == "complete" and " ✅ " or "  ○ "
                    self:settext(icon .. unlock.text)
                    if unlock.status == "complete" then
                        self:diffuse(color("#4CAF50"))
                    else
                        self:diffuse(color("#2196F3"))
                    end
                    self:visible(true)
                else
                    self:settext("")
                    self:visible(false)
                end
            else
                self:settext("")
                self:visible(false)
            end
        end,
    }
end

-- -----------------------------------------------------------------------
-- Avatar (same as achievements)

inner[#inner + 1] = Def.ActorFrame {
    InitCommand = function(self) self:xy(-40, -210):zoom(0.5) end,

    -- fallback avatar
    Def.ActorFrame {
        InitCommand = function(self) self:visible(true) end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            if params.index and avatars[params.index] then
                self:visible(false)
            else
                self:visible(true)
            end
        end,

        Def.Quad {
            InitCommand = function(self)
                self:align(0, 0):zoomto(avatar_dim, avatar_dim):diffuse(color("#283239aa"))
            end
        },
        LoadActor(THEME:GetPathG("", "_VisualStyles/" .. ThemePrefs.Get("VisualStyle") .. "/SelectColor")) .. {
            InitCommand = function(self)
                self:align(0, 0):zoom(0.09):diffusealpha(0.9):xy(13, 8)
            end
        },
        LoadFont("Common Normal") .. {
            Text = THEME:GetString("ProfileAvatar", "NoAvatar"),
            InitCommand = function(self)
                self:valign(0):zoom(0.815):diffusealpha(0.9):xy(self:GetWidth() * 0.5 + 13, 67)
            end,
        }
    },

    Def.Sprite {
        Name = "PlayerAvatar",
        InitCommand = function(self)
            self:align(0, 0):scaletoclipped(avatar_dim, avatar_dim)
        end,
        UnlockUpdateMessageCommand = function(self, params)
            if params.Player ~= player then return end
            if params.index and avatars[params.index] then
                self:Load(avatars[params.index]):visible(true)
            elseif params.index == 0 then
                self:Load(THEME:GetPathB("ScreenSelectProfile", "underlay/" .. "Cabby.png")):visible(true)
            else
                self:visible(false)
            end
        end
    },
}

t[#t + 1] = inner
return t
