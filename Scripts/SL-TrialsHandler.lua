-- SM5 Favorites manager by leadbman & modified for RIO by Rhythm Lunatic
-- Modified and implemented by Crash Cringle
-- Inhibit Regular Expression magic characters ^$()%.[]*+-?)
local function strPlainText(strText)
    -- Prefix every non-alphanumeric character (%W) with a % escape character,
    -- where %% is the % escape, and %1 is original character
    return strText:gsub("(%W)", "%%%1")
end

getTrialsPath = function(player)
    local path = THEME:GetPathO("", "Playlists/Trials.txt")
    return path;
end

getPlaylistPath = function(playlist)
    local path = THEME:GetPathO("", "Playlists/" .. playlist .. ".txt")
    return path;
end

generateTrialsForMusicWheel = function()
    SL.Global.Trials = {}
    SL.Global.TrialDiffs = {}
    local strToWrite = ""
    -- declare listoTrials inside the loop so that P1 and P2 can have independent lists
    local listoTrials = {}
    local path = getTrialsPath(pn)
    if FILEMAN:DoesFileExist(path) then
        local trials = lua.ReadFile(path)

        -- the txt file has been read into a string as `trials`
        -- ensure it isn't empty
        if trials:len() > 2 then

            -- If the first line of the Trials file doesn't begin with --- then it means 
            -- Either the player just added their first Trial or the player's file was in legacy Trial format
            -- In both cases let's ensure that going forward the first line is the header defining the Trial's section Name
            -- By default we set this to the {Profile Display Name}'s Trials
            if not trials:find("^---") then
                listoTrials[1] = {Name = "Cabby's Trials\n", Songs = {}}
            end
            local section = "Cabby's Trials"
            -- split it on newline characters and add each line as a string
            -- to the listoTrials table accordingly
            for line in trials:gmatch("[^\r\n]+") do
                --- If the line starts with "---" it's a header, so don't add it to the list of songs
                if line:find("^---") then
                    -- You could modify the TrialSongs.txt file to create custom sections when using the Preferred Sort (Trials)
                    -- Any line that begins with --- will be treated as the start of a new section
                    -- i.e. ---Cringle's Super Cool Stamina Playlist

                    -- Newly Triald songs will be added to your bottom-most section.
                    -- This is only relevant if you have modified your Trials file for custom sections.
                    listoTrials[#listoTrials + 1] = {
                        Name = line:gsub("---", ""),
                        Songs = {}
                    }
                    section = line:gsub("---", "")
                    SL.Global.TrialMap[section] = {}
                else
                    listoTrials[#listoTrials].Songs[#listoTrials[#listoTrials]
                        .Songs + 1] = {
                        Path = line,
                        Title = SONGMAN:FindSong(line) and
                            SONGMAN:FindSong(line):GetDisplayMainTitle() or nil
                    }
                    SL.Global.Trials[#SL.Global.Trials + 1] = SONGMAN:FindSong(
                                                                  line)
                    SL.Global.TrialMap[section][#SL.Global.TrialMap[section] + 1] =
                        SONGMAN:FindSong(line)
                end
            end

            -- sort alphabetically
            -- table.sort(listoTrials, function(a, b)
            --     return a.Name:lower() < b.Name:lower()
            -- end)
            for i = 1, #listoTrials do
                table.sort(listoTrials[i].Songs, function(a, b)
                    if a.Title == nil then
                        return false
                    elseif b.Title == nil then
                        return true
                    end
                    return a.Title:lower() < b.Title:lower()
                end)
            end

            -- append each group/song string to the overall strToWrite
            for fav, _ in ivalues(listoTrials) do
                strToWrite = strToWrite .. ("---%s\n"):format(fav.Name)
                for song, i in ivalues(fav.Songs) do
                    strToWrite = strToWrite .. ("%s\n"):format(song.Path)
                end
            end
        end
    else
        SM("No Trials found at " .. path)
    end

    if strToWrite ~= "" then
        local path = getTrialsPath(pn)
        local file = RageFileUtil.CreateRageFile()

        if file:Open(path, 2) then
            file:Write(strToWrite)
            file:Close()
            file:destroy()
        else
            SM("Could not open '" .. path .. "' to write current playing info.")
        end
    end

end
