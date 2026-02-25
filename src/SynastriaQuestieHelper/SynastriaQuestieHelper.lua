local addonName, addonTable = ...
local SynastriaQuestieHelper = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")

-- Constants
local CHAT_MSG_SYSTEM = "CHAT_MSG_SYSTEM"

-- State
SynastriaQuestieHelper.quests = {}
SynastriaQuestieHelper.totalQuestCount = 0
SynastriaQuestieHelper.isScanning = false
SynastriaQuestieHelper.isLoading = false
SynastriaQuestieHelper.coordCache = {}
SynastriaQuestieHelper.chainCache = {} -- Cache quest chains
SynastriaQuestieHelper.rewardCache = {} -- Cache quest rewards
SynastriaQuestieHelper.followUpCache = {} -- Cache: questId -> list of quests that require it as prerequisite
SynastriaQuestieHelper.questToRewardQuestCache = {} -- Cache: questId -> final quest in chain with rewards (if any)
SynastriaQuestieHelper.cachesBuilt = false -- Track if we've built starter caches
SynastriaQuestieHelper.questRealCache = {} -- Cache: questId -> is valid/real

function SynastriaQuestieHelper:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("SynastriaQuestieHelperDB", {
        profile = {
            hideCompleted = true, -- Hide completed quests by default
            showWrongFaction = false, -- Show quests for other faction
            showLevelTooLow = false, -- Show quests where player is below required level
            showCrossZoneChains = true, -- Show quest chains that span multiple zones
            persistWaypoints = false, -- Save waypoints between sessions
            framePos = {}, -- Store frame position and size
            transparency = 1.0, -- Window transparency (1.0 = opaque)
            backgroundTransparency = 0.8, -- Background transparency
            autoLoad = false, -- Automatically open window on login
            noCloseOnEsc = false, -- Prevent closing with ESC key
            minimapButton = {
                hide = false,
                position = 225,
            },
        },
    }, true)

    self:RegisterChatCommand("synastriaquestiehelper", "OnSlashCommand")
    self:RegisterChatCommand("sqh", "OnSlashCommand")
    
    -- Setup options
    self:SetupOptions()

    -- Create minimap button
    self:CreateMinimapButton()

    -- Register logout event to save window position
    self:RegisterEvent("PLAYER_LOGOUT")
end

function SynastriaQuestieHelper:PLAYER_LOGOUT()
    if self.frame and self.frame.frame and self.frame.frame:IsShown() then
        local status = self.frame.status or self.frame.localstatus
        if status then
            self.db.profile.framePos = {
                width = status.width,
                height = status.height,
                top = status.top,
                left = status.left,
            }
        end
    end
end

function SynastriaQuestieHelper:SetupOptions()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    
    local options = {
        name = "Synastria Questie Helper",
        type = "group",
        args = {
            general = {
                name = "General Settings",
                type = "group",
                order = 1,
                args = {
                    hideCompleted = {
                        name = "Hide Completed Quests",
                        desc = "Hide quests that have already been completed",
                        type = "toggle",
                        order = 1,
                        get = function() return self.db.profile.hideCompleted end,
                        set = function(_, value)
                            self.db.profile.hideCompleted = value
                        end,
                    },
                    showWrongFaction = {
                        name = "Show Wrong Faction Quests",
                        desc = "Show quests that are for the opposite faction (Alliance/Horde)",
                        type = "toggle",
                        order = 2,
                        get = function() return self.db.profile.showWrongFaction end,
                        set = function(_, value)
                            self.db.profile.showWrongFaction = value
                        end,
                    },
                    showLevelTooLow = {
                        name = "Show Quests Above Your Level",
                        desc = "Show quests where your level is below the minimum required level",
                        type = "toggle",
                        order = 3,
                        get = function() return self.db.profile.showLevelTooLow end,
                        set = function(_, value)
                            self.db.profile.showLevelTooLow = value
                        end,
                    },
                    showCrossZoneChains = {
                        name = "Show Cross-Zone Quest Chains",
                        desc = "Show quest chains where any quest in the chain is in the current zone (even if the final quest is in another zone)",
                        type = "toggle",
                        order = 4,
                        get = function() return self.db.profile.showCrossZoneChains end,
                        set = function(_, value)
                            self.db.profile.showCrossZoneChains = value
                        end,
                    },
                    persistWaypoints = {
                        name = "Persist TomTom Waypoints",
                        desc = "Save created waypoints between sessions (requires TomTom)",
                        type = "toggle",
                        order = 5,
                        get = function() return self.db.profile.persistWaypoints end,
                        set = function(_, value)
                            self.db.profile.persistWaypoints = value
                        end,
                    },
                },
            },
            window = {
                name = "Window Settings",
                type = "group",
                order = 2,
                args = {
                    transparency = {
                        name = "Master Transparency",
                        desc = "Adjust the transparency of the whole window (affects text and background)",
                        type = "range",
                        min = 0.1,
                        max = 1.0,
                        step = 0.05,
                        order = 1,
                        get = function() return self.db.profile.transparency end,
                        set = function(_, value)
                            self.db.profile.transparency = value
                            self:UpdateFrameTransparency()
                        end,
                    },
                    backgroundTransparency = {
                        name = "Background Transparency",
                        desc = "Adjust the transparency of the window background only",
                        type = "range",
                        min = 0.0,
                        max = 1.0,
                        step = 0.05,
                        order = 2,
                        get = function() return self.db.profile.backgroundTransparency end,
                        set = function(_, value)
                            self.db.profile.backgroundTransparency = value
                            self:UpdateFrameTransparency()
                        end,
                    },
                    autoLoad = {
                        name = "Auto Open on Login",
                        desc = "Automatically open the window when you log in or reload UI",
                        type = "toggle",
                        order = 2,
                        get = function() return self.db.profile.autoLoad end,
                        set = function(_, value)
                            self.db.profile.autoLoad = value
                        end,
                    },
                    noCloseOnEsc = {
                        name = "Do Not Close with ESC",
                        desc = "Prevent the window from closing when pressing the ESC key",
                        type = "toggle",
                        order = 3,
                        get = function() return self.db.profile.noCloseOnEsc end,
                        set = function(_, value)
                            self.db.profile.noCloseOnEsc = value
                            self:UpdateEscBehavior()
                        end,
                    },
                },
            },
        },
    }
    
    AceConfig:RegisterOptionsTable("SynastriaQuestieHelper", options)
    AceConfigDialog:AddToBlizOptions("SynastriaQuestieHelper", "Synastria Questie Helper")
end

function SynastriaQuestieHelper:CreateMinimapButton()
    local button = CreateFrame("Button", "SynastriaQuestieHelperMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    -- Icon background
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("CENTER", 0, 1)
    
    -- Icon
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\AddOns\\Questie-335\\Icons\\available")
    icon:SetPoint("CENTER", background, "CENTER", 0, 0)
    button.icon = icon
    
    -- Border
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT", 0, 0)
    
    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Synastria Questie Helper", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Toggle UI", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: Open Settings", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click handler
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            SynastriaQuestieHelper:ToggleUI()
        elseif btn == "RightButton" then
            -- Open settings panel
            InterfaceOptionsFrame_OpenToCategory("Synastria Questie Helper")
            InterfaceOptionsFrame_OpenToCategory("Synastria Questie Helper") -- Called twice due to Blizzard bug
        end
    end)
    
    -- Dragging
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self.isDragging = true
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self.isDragging = false
        local position = self:GetPosition()
        SynastriaQuestieHelper.db.profile.minimapButton.position = position
    end)
    
    button:SetScript("OnUpdate", function(self)
        if self.isDragging then
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            self:SetPosition(angle)
        end
    end)
    
    -- Position functions
    function button:SetPosition(angle)
        local x = math.cos(math.rad(angle))
        local y = math.sin(math.rad(angle))
        local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"
        local radius = (minimapShape == "SQUARE") and 85 or 80
        self:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
    end
    
    function button:GetPosition()
        local mx, my = Minimap:GetCenter()
        local bx, by = self:GetCenter()
        local angle = math.deg(math.atan2(by - my, bx - mx))
        return angle
    end
    
    -- Set initial position
    button:SetPosition(self.db.profile.minimapButton.position)
    
    -- Show/hide based on settings
    if self.db.profile.minimapButton.hide then
        button:Hide()
    end
    
    self.minimapButton = button
end

function SynastriaQuestieHelper:OnEnable()
    -- Called when the addon is enabled
    if self.db.profile.autoLoad then
        self:ToggleUI()
    end
end

function SynastriaQuestieHelper:OnSlashCommand(input)
    local command = tostring(input or ""):gsub("^%s*(.-)%s*$", "%1")
    if command == "toggle" then
        self:ToggleUI()
    elseif command == "reset" then
        self:ResetFramePosition()
    else
        self:Print("Usage: /synastriaquestiehelper or /sqh [toggle, reset]")
    end
end

function SynastriaQuestieHelper:ShowCopyableURL(url)
    local AceGUI = LibStub("AceGUI-3.0")
    if not AceGUI then return end
    
    -- Create or reuse popup frame
    if not self.urlPopup then
        local frame = AceGUI:Create("Frame")
        frame:SetTitle("Quest URL")
        frame:SetWidth(450)
        frame:SetHeight(150)
        frame:SetLayout("Flow")
        frame:SetCallback("OnClose", function(widget)
            widget:Hide()
        end)
        
        -- Make URL popup closable with ESC
        _G["SynastriaQuestieHelperURLFrame"] = frame.frame
        tinsert(UISpecialFrames, "SynastriaQuestieHelperURLFrame")
        
        -- Label
        local label = AceGUI:Create("Label")
        label:SetText("Press Ctrl+C to copy:")
        label:SetFullWidth(true)
        frame:AddChild(label)
        
        -- Edit box
        local editBox = AceGUI:Create("EditBox")
        editBox:SetFullWidth(true)
        editBox:DisableButton(true)
        editBox:SetCallback("OnEnterPressed", function(widget)
            frame:Hide()
        end)
        frame:AddChild(editBox)
        
        frame.urlEditBox = editBox
        self.urlPopup = frame
    end
    
    -- Set URL and show
    self.urlPopup.urlEditBox:SetText(url)
    self.urlPopup.urlEditBox:HighlightText()
    self.urlPopup.urlEditBox:SetFocus()
    self.urlPopup:Show()
end

function SynastriaQuestieHelper:ResetFramePosition()
    self.db.profile.framePos = {}
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
    self:Print("Frame position reset. Open the UI again to see the default position.")
end

function SynastriaQuestieHelper:AddTomTomWaypoint(x, y, zoneId, title)
    -- Check if TomTom is available
    if not TomTom then
        self:Print("TomTom is not installed or loaded.")
        return
    end
    
    -- Always get zone name (for both current and cross-zone)
    local zoneName = self:GetZoneName(zoneId)
    
    if zoneName then
        -- Build a zone list like TomTom does
        local zlist = {}
        for cidx, c in ipairs({GetMapContinents()}) do
            for zidx, z in ipairs({GetMapZones(cidx)}) do
                zlist[z:lower():gsub("[%L]", "")] = {cidx, zidx, z}
            end
        end
        
        -- Fuzzy match the zone name
        local matches = {}
        local searchZone = zoneName:lower():gsub("[%L]", "")
        
        for z, entry in pairs(zlist) do
            if z:match(searchZone) then
                table.insert(matches, entry)
            end
        end
        
        local uid
        if #matches == 1 then
            -- Found the zone, use AddZWaypoint directly with configurable persistence
            local c, z, name = unpack(matches[1])
            local persistent = self.db.profile.persistWaypoints
            uid = TomTom:AddZWaypoint(c, z, x, y, title or "Quest Location", persistent, true, true)
        else
            -- Fallback to /way command if we can't resolve the zone
            local wayCmd = string.format("%s %.1f %.1f %s", zoneName, x, y, title or "")
            SlashCmdList["TOMTOM_WAY"](wayCmd)
        end
        
        -- Set crazy arrow
        self:ScheduleTimer(function()
            if not uid and TomTom.waypoints then
                -- If we used /way command, find the waypoint
                for id, data in pairs(TomTom.waypoints) do
                    if data.title == (title or "") and 
                       data.x and data.y and
                       math.abs(data.x - x) < 0.5 and 
                       math.abs(data.y - y) < 0.5 then
                        uid = id
                        break
                    end
                end
            end
            
            if uid and TomTom.profile and TomTom.profile.arrow and TomTom.profile.arrow.arrival then
                TomTom:SetCrazyArrow(uid, TomTom.profile.arrow.arrival, title)
            end
        end, 0.1)
    else
        self:Print(string.format("Could not determine zone name. Coordinates: %.1f, %.1f", x, y))
    end
end

function SynastriaQuestieHelper:BuildStarterCache()
    if self.cachesBuilt or not self.QuestieDB then
        return
    end
    
    -- Build cache of quest starters in one pass
    if self.QuestieDB.NPCPointers then
        for npcId in pairs(self.QuestieDB.NPCPointers) do
            local questStarts = self.QuestieDB.QueryNPCSingle(npcId, "questStarts")
            if questStarts and type(questStarts) == "table" then
                local spawns = self.QuestieDB.QueryNPCSingle(npcId, "spawns")
                if spawns and type(spawns) == "table" then
                    for zoneId, coords in pairs(spawns) do
                        if coords and coords[1] and coords[1][1] and coords[1][2] then
                            -- Cache all quests started by this NPC
                            for _, questId in ipairs(questStarts) do
                                if not self.coordCache[questId] then
                                    self.coordCache[questId] = {x = coords[1][1], y = coords[1][2], zoneId = zoneId}
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Build cache of quest starters from objects
    if self.QuestieDB.ObjectPointers then
        for objId in pairs(self.QuestieDB.ObjectPointers) do
            local questStarts = self.QuestieDB.QueryObjectSingle(objId, "questStarts")
            if questStarts and type(questStarts) == "table" then
                local spawns = self.QuestieDB.QueryObjectSingle(objId, "spawns")
                if spawns and type(spawns) == "table" then
                    for zoneId, coords in pairs(spawns) do
                        if coords and coords[1] and coords[1][1] and coords[1][2] then
                            -- Cache all quests started by this object
                            for _, questId in ipairs(questStarts) do
                                if not self.coordCache[questId] then
                                    self.coordCache[questId] = {x = coords[1][1], y = coords[1][2], zoneId = zoneId}
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Build cache of follow-up quests (questId -> quests that require it as prerequisite)
    if self.QuestieDB.QuestPointers then
        for questId in pairs(self.QuestieDB.QuestPointers) do
            local success, questData = pcall(function() return self.QuestieDB.GetQuest(questId) end)
            if success and questData then
                -- Check preQuestSingle
                if questData.preQuestSingle then
                    local preq = questData.preQuestSingle
                    if type(preq) == "table" then
                        for _, prereqId in ipairs(preq) do
                            if not self.followUpCache[prereqId] then
                                self.followUpCache[prereqId] = {}
                            end
                            table.insert(self.followUpCache[prereqId], questId)
                        end
                    else
                        if not self.followUpCache[preq] then
                            self.followUpCache[preq] = {}
                        end
                        table.insert(self.followUpCache[preq], questId)
                    end
                end
                
                -- Check preQuestGroup
                if questData.preQuestGroup and type(questData.preQuestGroup) == "table" then
                    for _, prereqId in ipairs(questData.preQuestGroup) do
                        if not self.followUpCache[prereqId] then
                            self.followUpCache[prereqId] = {}
                        end
                        table.insert(self.followUpCache[prereqId], questId)
                    end
                end
            end
        end
    end
    
    self.cachesBuilt = true
end

function SynastriaQuestieHelper:ScanQuests()
    if self.isScanning then
        self:Print("Scan already in progress.")
        return
    end
    
    -- Check cooldown
    local now = GetTime()
    if self.lastScanTime and (now - self.lastScanTime) < 2 then
        local remaining = math.ceil(2 - (now - self.lastScanTime))
        self:Print(string.format("Scan on cooldown. %d seconds remaining.", remaining))
        return
    end

    self.isScanning = true
    self.isLoading = true
    self.quests = {} -- Clear previous results
    self.totalQuestCount = 0 -- Reset total count
    self.rewardCache = {} -- Clear reward cache so progress checks are fresh each scan
    self.questItemLookup = nil -- Rebuild item->quest lookup with current attune progress
    
    -- Update UI to show loading state
    self:UpdateQuestList()
    
    -- Lazy-load QuestieDB
    if not self.QuestieDB and QuestieLoader then
        self.QuestieDB = QuestieLoader:ImportModule("QuestieDB")
    end
    
    if not self.QuestieDB then
        self:Print("Questie addon not detected. Please install Questie.")
        self.isScanning = false
        self.isLoading = false
        return
    end
    
    -- Build starter cache on first scan
    if not self.cachesBuilt then
        self:BuildStarterCache()
    end
    
    -- Get current zone using GetRealZoneText
    local zoneName = GetRealZoneText()
    
    if not zoneName or zoneName == "" then
        self:Print("Could not detect current zone.")
        self.isScanning = false
        self.isLoading = false
        return
    end
    
    -- Lazy-load ZoneDB and C_Map compat
    if not self.ZoneDB and QuestieLoader then
        self.ZoneDB = QuestieLoader:ImportModule("ZoneDB")
    end
    if not self.C_Map and QuestieCompat then
        self.C_Map = QuestieCompat.C_Map
    end
    
    -- Find AreaId by matching zone name
    local zoneId = nil
    
    -- First check dungeons table (dungeons have names but may not be in C_Map)
    if self.ZoneDB and self.ZoneDB.private and self.ZoneDB.private.dungeons then
        for areaId, dungeonData in pairs(self.ZoneDB.private.dungeons) do
            if dungeonData[1] == zoneName then
                zoneId = areaId
                break
            end
        end
    end
    
    -- If not a dungeon, check regular zones via C_Map
    if not zoneId and self.ZoneDB and self.ZoneDB.private and self.ZoneDB.private.areaIdToUiMapId and self.C_Map then
        for areaId, uiMapId in pairs(self.ZoneDB.private.areaIdToUiMapId) do
            local mapInfo = self.C_Map.GetMapInfo(uiMapId)
            if mapInfo and mapInfo.name == zoneName then
                zoneId = areaId
                break
            end
        end
    end
    
    if not zoneId then
        self:Print(string.format("Could not find AreaId for zone: %s. Please report this issue.", zoneName))
        self.isScanning = false
        self.isLoading = false
        return
    end
    
    -- Store current zone ID for later use
    self.currentZoneId = zoneId
    
    
        -- Defer the actual scanning to next frame to allow UI to update
    self:ScheduleTimer(function()
        self:PerformQuestieScan(zoneId)
    end, 0.1)
end

function SynastriaQuestieHelper:IsQuestReal(questId)
    if not self.QuestieDB then return true end
    if self.questRealCache[questId] ~= nil then
        return self.questRealCache[questId]
    end
    
    -- Check if quest has any quest givers (startedBy) OR turn-in points (finishedBy)
    -- Beta/unavailable quests typically have no NPCs/objects to start or finish them
    local startedBy = self.QuestieDB.QueryQuestSingle(questId, "startedBy")
    local finishedBy = self.QuestieDB.QueryQuestSingle(questId, "finishedBy")
    
    local hasStarter = startedBy and type(startedBy) == "table" and (
        (startedBy[1] and #startedBy[1] > 0) or  -- has creature starters
        (startedBy[2] and #startedBy[2] > 0) or  -- has object starters
        (startedBy[3] and #startedBy[3] > 0))    -- has item starters
    
    local hasFinisher = finishedBy and type(finishedBy) == "table" and (
        (finishedBy[1] and #finishedBy[1] > 0) or  -- has creature finishers
        (finishedBy[2] and #finishedBy[2] > 0))    -- has object finishers
    
    -- Quest must have either a starter OR a finisher to be valid
    if not hasStarter and not hasFinisher then
        self.questRealCache[questId] = false
        return false
    end
    
    -- Check quest flags for UNAVAILABLE flag (bit 14 = 16384)
    local questFlags = self.QuestieDB.QueryQuestSingle(questId, "questFlags")
    if questFlags then
        local QUEST_FLAGS_UNAVAILABLE = 16384
        if bit.band(questFlags, QUEST_FLAGS_UNAVAILABLE) ~= 0 then
            self.questRealCache[questId] = false
            return false
        end
    end
    
    self.questRealCache[questId] = true
    return true
end

function SynastriaQuestieHelper:PerformQuestieScan(zoneId)
    if not self.QuestieDB or not self.QuestieDB.QuestPointers then
        self:Print("Questie database not available.")
        self:StopScanning()
        return
    end
    
    -- Lazy-load ZoneDB and QuestieCompat
    if not self.ZoneDB and QuestieLoader then
        self.ZoneDB = QuestieLoader:ImportModule("ZoneDB")
    end
    if not self.C_Map and QuestieCompat then
        self.C_Map = QuestieCompat.C_Map
    end
    
    local questsByZone = {} -- Group quests by zoneOrSort
    local checkedCount = 0
    local addedChainSignatures = {} -- Track chain signatures to avoid duplicate chains
    
    -- Iterate through all quests in Questie's database
    for questId, _ in pairs(self.QuestieDB.QuestPointers) do
        checkedCount = checkedCount + 1
        
        -- Skip beta/test/unavailable quests
        if not self:IsQuestReal(questId) then
            -- Skip this quest
        else
            -- Check if this quest has attunement rewards
            local itemDBRewards = self:GetQuestRewardsFromItemDB(questId)
            
            -- If this quest has no rewards, check if any follow-up quest in the chain has rewards
            if not itemDBRewards or #itemDBRewards == 0 then
                if self.followUpCache[questId] then
                    -- Check all follow-up quests recursively
                    local visited = {[questId] = true}
                    local toCheck = {}
                    local queueIndex = 1
                    for _, followUpId in ipairs(self.followUpCache[questId]) do
                        table.insert(toCheck, followUpId)
                    end
                    
                    while queueIndex <= #toCheck and (not itemDBRewards or #itemDBRewards == 0) do
                        local checkId = toCheck[queueIndex]
                        queueIndex = queueIndex + 1
                        if not visited[checkId] then
                            visited[checkId] = true
                            local followUpRewards = self:GetQuestRewardsFromItemDB(checkId)
                            if followUpRewards and #followUpRewards > 0 then
                                itemDBRewards = followUpRewards
                                break
                            end
                            -- Add this quest's follow-ups to check
                            if self.followUpCache[checkId] then
                                for _, nextFollowUpId in ipairs(self.followUpCache[checkId]) do
                                    table.insert(toCheck, nextFollowUpId)
                                end
                            end
                        end
                    end
                end
            end
            
            if itemDBRewards and #itemDBRewards > 0 then
                local questData = self.QuestieDB.GetQuest(questId)
                
                if questData and questData.name then
                    -- Check if this quest or any quest in its chain is in the current zone
                    local shouldInclude = false
                    local questZone = nil
                    
                    -- Check zoneOrSort first (fastest)
                    if questData.zoneOrSort and questData.zoneOrSort > 0 then
                        if questData.zoneOrSort == zoneId then
                            shouldInclude = true
                            questZone = zoneId
                        end
                    end
                    
                    -- Check extraObjectives for zone (dungeons often use this)
                    if not shouldInclude then
                        local extraObjectives = self.QuestieDB.QueryQuestSingle(questId, "extraObjectives")
                        if extraObjectives and type(extraObjectives) == "table" then
                            for _, objective in ipairs(extraObjectives) do
                                if objective and objective[1] and type(objective[1]) == "table" then
                                    for objZoneId, _ in pairs(objective[1]) do
                                        if objZoneId == zoneId then
                                            shouldInclude = true
                                            questZone = zoneId
                                            break
                                        end
                                    end
                                end
                                if shouldInclude then break end
                            end
                        end
                    end
                    
                    -- Also check regular objectives for zone information
                    if not shouldInclude then
                        local objectives = self.QuestieDB.QueryQuestSingle(questId, "objectives")
                        if objectives and type(objectives) == "table" then
                            -- objectives structure: {npcObjectives, gameObjectObjectives, itemObjectives}
                            -- Only check itemObjectives (objectives[3]) for drops
                            if objectives[3] and type(objectives[3]) == "table" then
                                for _, itemList in ipairs(objectives[3]) do
                                    if itemList and type(itemList) == "table" then
                                        for _, itemId in ipairs(itemList) do
                                            if itemId and self.QuestieDB.QueryItemSingle then
                                                local itemDrops = self.QuestieDB.QueryItemSingle(itemId, "npcDrops")
                                                if itemDrops and type(itemDrops) == "table" then
                                                    -- Check where the NPCs that drop this item spawn
                                                    for _, npcId in ipairs(itemDrops) do
                                                        if npcId and self.QuestieDB.QueryNPCSingle then
                                                            local npcSpawns = self.QuestieDB.QueryNPCSingle(npcId, "spawns")
                                                            if npcSpawns and type(npcSpawns) == "table" then
                                                                for spawnZoneId, _ in pairs(npcSpawns) do
                                                                    if spawnZoneId == zoneId then
                                                                        shouldInclude = true
                                                                        questZone = zoneId
                                                                        break
                                                                    end
                                                                end
                                                            end
                                                        end
                                                        if shouldInclude then break end
                                                    end
                                                end
                                            end
                                            if shouldInclude then break end
                                        end
                                    end
                                    if shouldInclude then break end
                                end
                            end
                        end
                    end
                    
                    -- Only check starter if zoneOrSort and extraObjectives didn't match
                    if not shouldInclude then
                        local starterX, starterY, starterZoneId = self:GetQuestStarterCoords(questId)
                        if starterZoneId == zoneId then
                            shouldInclude = true
                            questZone = zoneId
                        elseif not questZone then
                            -- Use starter zone as fallback if no zoneOrSort
                            questZone = starterZoneId
                        end
                    end
                    
                    -- If still not included, check chain if cross-zone is enabled
                    if not shouldInclude and self.db.profile.showCrossZoneChains then
                        -- Get chain once and cache it
                        local chain = self:GetQuestChain(questId)
                        for _, chainQuest in ipairs(chain) do
                            -- Skip checking the quest we already checked
                            if chainQuest.id ~= questId then
                                local chainQuestData = self.QuestieDB.GetQuest(chainQuest.id)
                                if chainQuestData then
                                    -- Check zoneOrSort first
                                    if chainQuestData.zoneOrSort and chainQuestData.zoneOrSort > 0 then
                                        if chainQuestData.zoneOrSort == zoneId then
                                            shouldInclude = true
                                            break
                                        end
                                    end
                                    
                                    -- Check extraObjectives
                                    if not shouldInclude then
                                        local chainExtraObjectives = self.QuestieDB.QueryQuestSingle(chainQuest.id, "extraObjectives")
                                        if chainExtraObjectives and type(chainExtraObjectives) == "table" then
                                            for _, objective in ipairs(chainExtraObjectives) do
                                                if objective and objective[1] and type(objective[1]) == "table" then
                                                    for objZoneId, _ in pairs(objective[1]) do
                                                        if objZoneId == zoneId then
                                                            shouldInclude = true
                                                            break
                                                        end
                                                    end
                                                end
                                                if shouldInclude then break end
                                            end
                                        end
                                    end
                                    
                                    -- Check regular objectives
                                    if not shouldInclude then
                                        local chainObjectives = self.QuestieDB.QueryQuestSingle(chainQuest.id, "objectives")
                                        if chainObjectives and type(chainObjectives) == "table" then
                                            for _, objective in ipairs(chainObjectives) do
                                                if objective and type(objective) == "table" and objective[3] then
                                                    if type(objective[3]) == "table" then
                                                        for objZoneId, _ in pairs(objective[3]) do
                                                            if objZoneId == zoneId then
                                                                shouldInclude = true
                                                                break
                                                            end
                                                        end
                                                    end
                                                end
                                                if shouldInclude then break end
                                            end
                                        end
                                    end
                                    
                                    -- Only check starter if zoneOrSort didn't match
                                    if not shouldInclude then
                                        local chainStarterX, chainStarterY, chainStarterZoneId = self:GetQuestStarterCoords(chainQuest.id)
                                        if chainStarterZoneId == zoneId then
                                            shouldInclude = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    if shouldInclude then
                        -- Only add this quest if it's not a prerequisite for another quest with rewards in the same zone
                        -- This prevents showing intermediate quests as separate chains
                        local isPrerequisite = false
                        
                        -- Use followUpCache to quickly check if any follow-up quest has rewards in this zone
                        if self.followUpCache[questId] then
                            for _, followUpId in ipairs(self.followUpCache[questId]) do
                                local followUpRewards = self:GetQuestRewardsFromItemDB(followUpId)
                                if followUpRewards and #followUpRewards > 0 then
                                    -- This quest has a follow-up with rewards, check if follow-up is in current zone
                                    local followUpData = self.QuestieDB.GetQuest(followUpId)
                                    if followUpData then
                                        local followUpInZone = false
                                        
                                        if followUpData.zoneOrSort == zoneId then
                                            followUpInZone = true
                                        else
                                            local followUpStarterX, followUpStarterY, followUpStarterZoneId = self:GetQuestStarterCoords(followUpId)
                                            if followUpStarterZoneId == zoneId then
                                                followUpInZone = true
                                            end
                                        end
                                        
                                        if followUpInZone then
                                            isPrerequisite = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        
                        if not isPrerequisite then
                            -- Create a chain signature to detect duplicate chains
                            local chain = self:GetQuestChain(questId)
                            local chainIds = {}
                            for _, chainQuest in ipairs(chain) do
                                table.insert(chainIds, chainQuest.id)
                            end
                            table.sort(chainIds)
                            local chainSignature = table.concat(chainIds, ",")
                            
                            -- Check if we've already added this chain
                            if not addedChainSignatures[chainSignature] then
                                addedChainSignatures[chainSignature] = true
                                
                                -- Group by the final quest's zone (or use zoneId if unknown)
                                local targetZone = questZone or zoneId
                                if not questsByZone[targetZone] then
                                    questsByZone[targetZone] = {}
                                end
                                
                                table.insert(questsByZone[targetZone], {
                                    id = questId,
                                    name = questData.name,
                                    reward = nil
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Check if current zone has quests
    if questsByZone[zoneId] and #questsByZone[zoneId] > 0 then
        local zoneName = "Unknown"
        
        -- Get zone name from ZoneDB
        if self.ZoneDB and self.C_Map then
            local uiMapId = self.ZoneDB:GetUiMapIdByAreaId(zoneId)
            if uiMapId then
                local mapInfo = self.C_Map.GetMapInfo(uiMapId)
                if mapInfo then
                    zoneName = mapInfo.name
                end
            end
        end
        
        self.quests = questsByZone[zoneId]
        self.totalQuestCount = #self.quests
    else
        self.quests = {}
        self.totalQuestCount = 0
    end
    
    self:StopScanning()
end

function SynastriaQuestieHelper:TableSize(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function SynastriaQuestieHelper:StopScanning()
    self.isScanning = false
    self.isLoading = false
    self.lastScanTime = GetTime() -- Record scan time for cooldown
    self:UpdateQuestList()
end

function SynastriaQuestieHelper:IsRewardItemEligible(itemId)
    if not itemId then
        return false
    end

    local canAttune = CanAttuneItemHelper(itemId)
    local isAttunable = (canAttune == true or canAttune == 1)
    local itemTags = GetItemTagsCustom and GetItemTagsCustom(itemId)
    local hasRequiredTags = itemTags and bit.band(itemTags, 96) == 64 -- Has this item been attuned?

    return isAttunable
        and GetItemAttuneProgress(itemId) == 0
        and GetItemAttuneForge(itemId) == -1
        and hasRequiredTags
end

function SynastriaQuestieHelper:BuildQuestItemLookup()
    if self.questItemLookup then return end
    
    self.questItemLookup = {}
    
    -- Lazy-load QuestieDB
    if not self.QuestieDB and QuestieLoader then
        self.QuestieDB = QuestieLoader:ImportModule("QuestieDB")
    end
    
    if not self.QuestieDB or not self.QuestieDB.ItemPointers then
        return
    end
    
    -- Build reverse lookup: questId -> {items that reward it}
    for itemId, _ in pairs(self.QuestieDB.ItemPointers) do
        -- Only check attunable items to reduce work
        if self:IsRewardItemEligible(itemId) then
            local questRewards = self.QuestieDB.QueryItemSingle(itemId, "questRewards")
            if questRewards and type(questRewards) == "table" then
                for _, rewardQuestId in ipairs(questRewards) do
                    if not self.questItemLookup[rewardQuestId] then
                        self.questItemLookup[rewardQuestId] = {}
                    end
                    table.insert(self.questItemLookup[rewardQuestId], {id = itemId, isChoice = false})
                end
            end
        end
    end
end

-- Get quest rewards by searching the item database
-- Returns a table of item IDs that list this quest as a reward
function SynastriaQuestieHelper:GetQuestRewardsFromItemDB(questId)
    -- Build lookup table once on first call
    if not self.questItemLookup then
        self:BuildQuestItemLookup()
    end
    
    return self.questItemLookup[questId] or {}
end

-- Get quest starter coordinates from Questie (uses pre-built cache)
function SynastriaQuestieHelper:GetQuestStarterCoords(questId)
    if not self.QuestieDB then return nil end
    
    -- Check cache (should always be populated after BuildStarterCache)
    if self.coordCache[questId] ~= nil then
        local cached = self.coordCache[questId]
        if cached and cached.x then
            return cached.x, cached.y, cached.zoneId
        else
            return nil -- Cached negative result
        end
    end
    
    -- Cache miss (shouldn't happen after BuildStarterCache, but handle it)
    return nil
end

-- Get zone name from zoneId
function SynastriaQuestieHelper:GetZoneName(zoneId)
    if not zoneId then return nil end
    
    -- Lazy-load ZoneDB and C_Map
    if not self.ZoneDB and QuestieLoader then
        self.ZoneDB = QuestieLoader:ImportModule("ZoneDB")
    end
    if not self.C_Map and QuestieCompat then
        self.C_Map = QuestieCompat.C_Map
    end
    
    if self.ZoneDB and self.C_Map then
        local uiMapId = self.ZoneDB:GetUiMapIdByAreaId(zoneId)
        if uiMapId then
            local mapInfo = self.C_Map.GetMapInfo(uiMapId)
            if mapInfo then
                return mapInfo.name
            end
        end
    end
    
    return nil
end

-- Get the full quest chain leading to this quest using Questie
function SynastriaQuestieHelper:GetQuestChain(questId)
    -- Check cache first
    if self.chainCache[questId] then
        return self.chainCache[questId]
    end
    
    local chain = {}
    local current = questId
    local visited = {} -- Prevent infinite loops
    
    -- Lazy-load QuestieDB
    if not self.QuestieDB and QuestieLoader then
        self.QuestieDB = QuestieLoader:ImportModule("QuestieDB")
        if not self.QuestieDB then
            if not self.questieWarningShown then
                self:Print("Questie addon not detected or failed to load. Quest chains will not be displayed.")
                self.questieWarningShown = true
            end
            return chain
        end
    end
    
    -- First, go backwards to find the start of the chain
    while current and not visited[current] do
        visited[current] = true
        
        if self.QuestieDB and self.QuestieDB.GetQuest then
            local success, questData = pcall(function() return self.QuestieDB.GetQuest(current) end)
            
            if success and questData then
                -- Skip beta/test quests in chain
                if self:IsQuestReal(current) then
                    -- preQuestSingle might be a table with quest IDs
                    local preQuest = nil
                    if questData.preQuestSingle then
                        if type(questData.preQuestSingle) == "table" then
                            preQuest = questData.preQuestSingle[1]
                        else
                            preQuest = questData.preQuestSingle
                        end
                    elseif questData.preQuestGroup and type(questData.preQuestGroup) == "table" then
                        preQuest = questData.preQuestGroup[1]
                    end
                    
                    table.insert(chain, 1, { 
                        id = current, 
                        name = questData.name or "Unknown"
                    })
                    current = preQuest
                else
                    -- Skip this beta quest and continue with its prerequisite
                    local preQuest = nil
                    if questData.preQuestSingle then
                        if type(questData.preQuestSingle) == "table" then
                            preQuest = questData.preQuestSingle[1]
                        else
                            preQuest = questData.preQuestSingle
                        end
                    elseif questData.preQuestGroup and type(questData.preQuestGroup) == "table" then
                        preQuest = questData.preQuestGroup[1]
                    end
                    current = preQuest
                end
            else
                -- Failed to get quest data
                break
            end
        else
            break
        end
    end
    
    -- Now go forwards from the last quest in the chain to find follow-up quests
    if #chain > 0 then
        local lastQuest = chain[#chain].id
        current = lastQuest
        visited = {[lastQuest] = true} -- Reset visited but mark the last quest
        
        while current do
            local success, questData = pcall(function() return self.QuestieDB.GetQuest(current) end)
            
            if success and questData then
                local nextQuest = questData.nextQuestInChain
                
                -- If nextQuestInChain is not set or is 0, check the follow-up cache
                if (not nextQuest or nextQuest == 0) and self.followUpCache[current] then
                    local followUps = self.followUpCache[current]
                    -- Pick the first valid follow-up quest
                    for _, followUpId in ipairs(followUps) do
                        if not visited[followUpId] and self:IsQuestReal(followUpId) then
                            nextQuest = followUpId
                            break
                        end
                    end
                end
                
                if nextQuest and not visited[nextQuest] then
                    visited[nextQuest] = true
                    
                    -- Get the next quest's data
                    local nextSuccess, nextQuestData = pcall(function() return self.QuestieDB.GetQuest(nextQuest) end)
                    if nextSuccess and nextQuestData and self:IsQuestReal(nextQuest) then
                        table.insert(chain, {
                            id = nextQuest,
                            name = nextQuestData.name or "Unknown"
                        })
                        current = nextQuest
                    else
                        break
                    end
                else
                    break
                end
            else
                break
            end
        end
    end
    
    -- Cache the result
    self.chainCache[questId] = chain
    
    return chain
end

function SynastriaQuestieHelper:UpdateFrameTransparency()
    if self.frame and self.frame.frame then
        -- Set master transparency (affects everything)
        self.frame.frame:SetAlpha(self.db.profile.transparency)
        
        -- Set background transparency
        -- AceGUI frames use SetBackdropColor for the background
        -- We keep the color black (0,0,0) and just adjust alpha
        self.frame.frame:SetBackdropColor(0, 0, 0, self.db.profile.backgroundTransparency)
        
        -- Also apply to border
        -- Default AceGUI border is usually white/greyish. We'll set it to white with the requested alpha.
        self.frame.frame:SetBackdropBorderColor(0.2, 0.2, 0.2, self.db.profile.backgroundTransparency)
    end
end

function SynastriaQuestieHelper:UpdateEscBehavior()
    -- Note: This might require a reload or re-opening the frame to fully take effect 
    -- depending on how Blizzard handles the UISpecialFrames table dynamically.
    -- But we try to update it live.
    
    local frameName = "SynastriaQuestieHelperMainFrame"
    local foundIndex = nil
    
    for i, name in ipairs(UISpecialFrames) do
        if name == frameName then
            foundIndex = i
            break
        end
    end
    
    if self.db.profile.noCloseOnEsc then
        -- Remove from UISpecialFrames if present
        if foundIndex then
            table.remove(UISpecialFrames, foundIndex)
        end
    else
        -- Add to UISpecialFrames if not present
        if not foundIndex then
            table.insert(UISpecialFrames, frameName)
        end
    end
end

function SynastriaQuestieHelper:ToggleUI()
    if not self.frame then
        self:CreateUI()
        return -- Frame is shown on creation
    end
    
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function SynastriaQuestieHelper:CreateUI()
    local AceGUI = LibStub("AceGUI-3.0")
    if not AceGUI then return end
    
    -- Main Frame
    local frame = AceGUI:Create("Frame")
    local titleText = "Synastria Questie Helper"
    if self.totalQuestCount > 0 then
        titleText = string.format("Synastria Questie Helper (%d quests)", self.totalQuestCount)
    end
    frame:SetTitle(titleText)
    frame:SetCallback("OnClose", function(widget)
        -- Save position and size before closing
        local status = widget.status or widget.localstatus
        if status then
            self.db.profile.framePos = {
                width = status.width,
                height = status.height,
                top = status.top,
                left = status.left,
            }
        end
        AceGUI:Release(widget)
        self.frame = nil
    end)
    frame:SetLayout("Flow")
    
    -- Set frame strata lower so map appears on top
    frame.frame:SetFrameStrata("MEDIUM")
    
    -- Restore saved position/size or use defaults
    local pos = self.db.profile.framePos
    if pos and pos.width then
        frame:SetWidth(pos.width)
        frame:SetHeight(pos.height)
        if pos.top and pos.left then
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left, pos.top)
        end
    else
        frame:SetWidth(400)
        frame:SetHeight(400)
    end
    
    -- Make frame closable with ESC without blocking keyboard input
    _G["SynastriaQuestieHelperMainFrame"] = frame.frame
    
    -- Apply ESC behavior setting
    if not self.db.profile.noCloseOnEsc then
        tinsert(UISpecialFrames, "SynastriaQuestieHelperMainFrame")
    end
    
    -- Apply transparency
    self:UpdateFrameTransparency()
    
    self.frame = frame
    
    -- Create scan button with AceGUI for consistent styling
    local scanBtn = AceGUI:Create("Button")
    scanBtn:SetText("Scan Zone")
    scanBtn:SetWidth(100)
    scanBtn:SetHeight(22)
    scanBtn:SetCallback("OnClick", function() self:ScanQuests() end)
    
    -- Position it manually next to close button
    scanBtn.frame:SetParent(frame.frame)
    scanBtn.frame:ClearAllPoints()
    scanBtn.frame:SetPoint("BOTTOMRIGHT", frame.frame, "BOTTOMRIGHT", -132, 16)
    scanBtn.frame:SetFrameLevel(frame.frame:GetFrameLevel() + 10)
    scanBtn.frame:Show()
    
    self.scanButton = scanBtn
    
    -- Scroll Frame for List
    local scrollContainer = AceGUI:Create("SimpleGroup")
    scrollContainer:SetFullWidth(true)
    scrollContainer:SetFullHeight(true)
    scrollContainer:SetLayout("Fill")
    frame:AddChild(scrollContainer)
    
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scrollContainer:AddChild(scroll)
    self.scroll = scroll
    
    self:UpdateQuestList()
end

-- Get quest status
function SynastriaQuestieHelper:GetQuestStatus(questId)
    -- Check if completed using Questie (if available)
    if Questie and Questie.db and Questie.db.char and Questie.db.char.complete then
        if Questie.db.char.complete[questId] then
            return "completed"
        end
    end
    
    -- Check if in quest log (accepted)
    -- In 3.3.5a, GetQuestLogTitle returns questID as the 9th parameter
    local numEntries, numQuests = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID = GetQuestLogTitle(i)
        if not isHeader and questID == questId then
            return "accepted"
        end
    end
    
    -- Check if prerequisites are met (if not, it's unavailable)
    local chain = self:GetQuestChain(questId)
    for i, chainQuest in ipairs(chain) do
        if chainQuest.id == questId then
            -- Found this quest in the chain, check if previous quest is completed
            if i > 1 then
                local prevQuest = chain[i-1]
                local prevStatus = "unknown"
                
                -- Check if previous quest is completed
                if Questie and Questie.db and Questie.db.char and Questie.db.char.complete then
                    if not Questie.db.char.complete[prevQuest.id] then
                        -- Previous quest not completed = this quest is unavailable
                        return "unavailable"
                    end
                end
            end
            break
        end
    end
    
    -- Not completed, not in log, prerequisites met = available
    return "available"
end

-- Helper to get rewards from quest log if quest is accepted
function SynastriaQuestieHelper:GetQuestLogRewards(questId)
    -- Check cache first
    local cacheKey = "log_" .. questId
    if self.rewardCache[cacheKey] then
        return self.rewardCache[cacheKey]
    end
    
    local rewards = {}
    
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, qId = GetQuestLogTitle(i)
        if not isHeader and qId == questId then
            -- Select this quest to query rewards
            SelectQuestLogEntry(i)
            
            -- Get choice rewards (player picks one)
            local numChoices = GetNumQuestLogChoices()
            for j = 1, numChoices do
                local name, texture, numItems, quality, isUsable = GetQuestLogChoiceInfo(j)
                if name then
                    -- Extract item ID from the link
                    local itemLink = GetQuestLogItemLink("choice", j)
                    if itemLink then
                        local itemId = CustomExtractItemId(itemLink)
                        if self:IsRewardItemEligible(itemId) then
                            table.insert(rewards, {id = itemId, isChoice = true})
                        end
                    end
                end
            end
            
            -- Get fixed rewards (player gets all)
            local numRewards = GetNumQuestLogRewards()
            for j = 1, numRewards do
                local name, texture, numItems, quality, isUsable = GetQuestLogRewardInfo(j)
                if name then
                    local itemLink = GetQuestLogItemLink("reward", j)
                    if itemLink then
                        local itemId = CustomExtractItemId(itemLink)
                        if self:IsRewardItemEligible(itemId) then
                            table.insert(rewards, {id = itemId, isChoice = false})
                        end
                    end
                end
            end
            
            break
        end
    end
    
    -- Cache the result
    self.rewardCache[cacheKey] = rewards
    
    return rewards
end

-- Check if player's race is compatible with quest requirement
function SynastriaQuestieHelper:IsQuestForPlayerFaction(questId)
    if not self.QuestieDB then return true end
    
    local requiredRaces = self.QuestieDB.QueryQuestSingle(questId, "requiredRaces")
    
    -- If there's a race requirement, check it
    if requiredRaces and requiredRaces ~= 0 then
        -- Get player's race
        local _, playerRace = UnitRace("player")
        if not playerRace then return true end
        
        -- Lazy-load race keys from QuestieDB
        if not self.raceKeys and self.QuestieDB and self.QuestieDB.raceKeys then
            self.raceKeys = self.QuestieDB.raceKeys
        end
        
        if not self.raceKeys then return true end
        
        -- Map player race name to bitmask value
        -- UnitRace returns: Human, Orc, Dwarf, NightElf, Scourge (Undead), Tauren, Gnome, Troll, BloodElf, Draenei
        local raceMap = {
            ["Human"] = self.raceKeys.HUMAN,
            ["Orc"] = self.raceKeys.ORC,
            ["Dwarf"] = self.raceKeys.DWARF,
            ["NightElf"] = self.raceKeys.NIGHT_ELF,
            ["Scourge"] = self.raceKeys.UNDEAD, -- Undead is called "Scourge" by UnitRace
            ["Tauren"] = self.raceKeys.TAUREN,
            ["Gnome"] = self.raceKeys.GNOME,
            ["Troll"] = self.raceKeys.TROLL,
            ["BloodElf"] = self.raceKeys.BLOOD_ELF,
            ["Draenei"] = self.raceKeys.DRAENEI,
        }
        
        local raceMask = raceMap[playerRace]
        if not raceMask then return true end
        
        -- Check if player's race is in the bitmask
        return bit.band(requiredRaces, raceMask) ~= 0
    end
    
    -- If no race requirement, assume quest is available
    return true
end

-- Check if quest level is appropriate for player
function SynastriaQuestieHelper:GetQuestLevelInfo(questId)
    if not self.QuestieDB then return nil, nil end
    
    local requiredLevel = self.QuestieDB.QueryQuestSingle(questId, "requiredLevel") or 1
    local questLevel = self.QuestieDB.QueryQuestSingle(questId, "questLevel") or requiredLevel
    local playerLevel = UnitLevel("player")
    
    local levelDiff = questLevel - playerLevel
    local tooLow = playerLevel < requiredLevel
    local veryHigh = levelDiff > 5
    
    return {
        requiredLevel = requiredLevel,
        questLevel = questLevel,
        playerLevel = playerLevel,
        tooLow = tooLow,
        veryHigh = veryHigh,
        levelDiff = levelDiff
    }
end

function SynastriaQuestieHelper:AddNonAttunementQuestLogSection()
    if not self.scroll then return end
    
    -- Only show if we have loaded quest data (not during loading)
    if self.isLoading or not self.quests or #self.quests == 0 then
        return
    end
    
    local AceGUI = LibStub("AceGUI-3.0")
    
    -- Build a set of ALL quest IDs that lead to attunable items (regardless of zone)
    -- For each quest in the log, we'll check if its full chain has attunable rewards
    local attunableQuestIds = {}
    
    -- Helper function to check if a quest or any in its chain has attunable rewards
    local function hasAttunableInChain(questId)
        if attunableQuestIds[questId] ~= nil then
            return attunableQuestIds[questId]
        end
        
        -- Get the full chain (forward to final quest)
        local chain = self:GetQuestChain(questId)
        if #chain == 0 then
            chain = {{id = questId}}
        end
        
        -- Check if any quest in the chain has attunable rewards
        local result = false
        for _, chainQuest in ipairs(chain) do
            local itemDBRewards = self:GetQuestRewardsFromItemDB(chainQuest.id)
            if itemDBRewards and #itemDBRewards > 0 then
                result = true
                break
            end
        end
        
        -- Cache the result for all quests in this chain
        for _, chainQuest in ipairs(chain) do
            attunableQuestIds[chainQuest.id] = result
        end
        
        return result
    end
    
    -- Scan quest log for quests that don't lead to attunable items
    local nonAttunementQuests = {}
    local numEntries = GetNumQuestLogEntries()
    
    for i = 1, numEntries do
        local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questId = GetQuestLogTitle(i)
        if not isHeader and questId then
            -- Use the helper function to check if this quest leads to attunable items
            if not hasAttunableInChain(questId) then
                table.insert(nonAttunementQuests, {
                    id = questId,
                    name = title,
                    level = level,
                })
            end
        end
    end
    
    -- Only show section if there are non-attunable quests
    if #nonAttunementQuests > 0 then
        -- Create collapsible header
        local headerBtn = AceGUI:Create("Button")
        headerBtn:SetText(string.format("Quest Log (%d non-attunable)", #nonAttunementQuests))
        headerBtn:SetFullWidth(true)
        headerBtn:SetHeight(22)
        
        -- Store collapsed state
        if self.nonAttunableCollapsed == nil then
            self.nonAttunableCollapsed = true -- Start collapsed
        end
        
        headerBtn:SetCallback("OnClick", function()
            self.nonAttunableCollapsed = not self.nonAttunableCollapsed
            self:UpdateQuestList()
        end)
        
        self.scroll:AddChild(headerBtn)
        
        -- Show quests if not collapsed
        if not self.nonAttunableCollapsed then
            for _, quest in ipairs(nonAttunementQuests) do
                local questLabel = AceGUI:Create("Label")
                questLabel:SetText(string.format("  [%d] %s", quest.level, quest.name))
                questLabel:SetFullWidth(true)
                questLabel:SetColor(0.7, 0.7, 0.7)
                
                -- Make clickable to show wowhead link
                local labelFrame = questLabel.frame
                if labelFrame then
                    labelFrame:EnableMouse(true)
                    labelFrame:SetScript("OnMouseDown", function(frame, button)
                        if button == "RightButton" then
                            local url = string.format("https://www.wowhead.com/wotlk/quest=%d", quest.id)
                            self:ShowCopyableURL(url)
                        end
                    end)
                    labelFrame:SetScript("OnEnter", function(frame)
                        local label = frame:GetChildren()
                        if label then
                            label:SetAlpha(0.7)
                        end
                    end)
                    labelFrame:SetScript("OnLeave", function(frame)
                        local label = frame:GetChildren()
                        if label then
                            label:SetAlpha(1.0)
                        end
                    end)
                end
                
                self.scroll:AddChild(questLabel)
            end
            
            -- Add spacing after section
            local spacer = AceGUI:Create("Label")
            spacer:SetText(" ")
            spacer:SetFullWidth(true)
            self.scroll:AddChild(spacer)
        end
    end
end

function SynastriaQuestieHelper:UpdateQuestList()
    if not self.scroll then return end
    self.scroll:ReleaseChildren()
    
    -- Update frame title with quest count
    if self.frame then
        local titleText = "Synastria Questie Helper"
        if self.totalQuestCount > 0 then
            titleText = string.format("Synastria Questie Helper (%d quests)", self.totalQuestCount)
        end
        self.frame:SetTitle(titleText)
    end
    
    local AceGUI = LibStub("AceGUI-3.0")
    
    -- Show loading message if scanning
    if self.isLoading then
        local loadingLabel = AceGUI:Create("Label")
        loadingLabel:SetText("Loading...")
        loadingLabel:SetFullWidth(true)
        loadingLabel:SetColor(1, 1, 1)
        loadingLabel:SetFont(GameFontNormal:GetFont(), 14, "OUTLINE")
        self.scroll:AddChild(loadingLabel)
        return
    end
    
    for _, quest in ipairs(self.quests) do
        -- Skip beta/test quests
        if not self:IsQuestReal(quest.id) then
            -- Skip this quest entirely
        else
            -- Get quest chain
            local chain = self:GetQuestChain(quest.id)
            
            -- If no chain found, create a single-item chain
            if #chain == 0 then
                chain = {{id = quest.id, name = quest.name}}
            end
        
        -- Get rewards for quests in the chain
        local chainRewards = {}
        for _, chainQuest in ipairs(chain) do
            -- Get rewards from quest log if accepted
            local logRewards = self:GetQuestLogRewards(chainQuest.id)
            -- Get rewards from item database
            local itemDBRewards = self:GetQuestRewardsFromItemDB(chainQuest.id)
            
            -- Merge rewards, preferring quest log data when available
            if logRewards and #logRewards > 0 then
                chainRewards[chainQuest.id] = logRewards
            elseif itemDBRewards and #itemDBRewards > 0 then
                chainRewards[chainQuest.id] = itemDBRewards
            end
        end
        
        -- Create simplified header (no collapse functionality)
        local headerLabel = AceGUI:Create("Label")
        local rewardCount = 0
        for _ in pairs(chainRewards) do rewardCount = rewardCount + 1 end
        
        -- Find the next available quest in the chain (first non-completed quest)
        local nextAvailableQuest = nil
        for _, chainQuest in ipairs(chain) do
            local status = self:GetQuestStatus(chainQuest.id)
            if status ~= "completed" then
                nextAvailableQuest = chainQuest
                break
            end
        end
        
        -- Use the next available quest for faction/level checks, or the final quest if all completed
        local checkQuestId = nextAvailableQuest and nextAvailableQuest.id or quest.id
        
        -- Check faction and level compatibility for the next available quest
        local wrongFaction = not self:IsQuestForPlayerFaction(checkQuestId)
        local levelInfo = self:GetQuestLevelInfo(checkQuestId)
        local levelTooLow = levelInfo and levelInfo.tooLow
        
        -- Skip quest if it doesn't match filter settings
        if (wrongFaction and not self.db.profile.showWrongFaction) or
           (levelTooLow and not self.db.profile.showLevelTooLow) then
            -- Skip this quest based on filter settings
        else
            -- First, check if any quest in the chain will be displayed
            local hasVisibleQuests = false
            for i, chainQuest in ipairs(chain) do
                local status = self:GetQuestStatus(chainQuest.id)
                if not (self.db.profile.hideCompleted and status == "completed") then
                    hasVisibleQuests = true
                    break
                end
            end
            
            -- Only show header and chain if there are visible quests
            if hasVisibleQuests then
                -- Build header with warnings
                local headerText = quest.name
                local warnings = {}
            
                if wrongFaction then
                    table.insert(warnings, "Wrong Faction")
                end
                if levelInfo and levelInfo.tooLow then
                    table.insert(warnings, string.format("Requires Level %d", levelInfo.requiredLevel))
                end
                
                if #warnings > 0 then
                    headerText = headerText .. " [" .. table.concat(warnings, ", ") .. "]"
                end
                
                headerLabel:SetText(headerText)
                headerLabel:SetFullWidth(true)
                
                -- Color header: red if wrong faction or too low level, gold otherwise
                if wrongFaction or (levelInfo and levelInfo.tooLow) then
                    headerLabel:SetColor(1, 0.3, 0.3) -- Red for unavailable
                else
                    headerLabel:SetColor(1, 0.82, 0) -- Gold for normal
                end
                
                headerLabel:SetFont(GameFontNormal:GetFont(), 14, "OUTLINE")
                self.scroll:AddChild(headerLabel)
                
                -- Always show chain (no collapse)
                for i, chainQuest in ipairs(chain) do
                    local status = self:GetQuestStatus(chainQuest.id)
                    
                    -- Check if we should hide completed quests
                    if not (self.db.profile.hideCompleted and status == "completed") then
                    local chainLabel = AceGUI:Create("Label")
                    
                    -- Use numbers for all quests in chain
                    local prefix = string.format("  %d. ", i)
                    
                    -- Check faction and level compatibility for this quest
                    local questWrongFaction = not self:IsQuestForPlayerFaction(chainQuest.id)
                    local questLevelInfo = self:GetQuestLevelInfo(chainQuest.id)
                    local questTooLow = questLevelInfo and questLevelInfo.tooLow
                    local isUnavailableToPlayer = questWrongFaction or questTooLow
                    
                    -- Add coordinates and level info for quests
                    local questText = chainQuest.name
                    local coordX, coordY, coordZone
                    
                    -- Add level info
                    if questLevelInfo and questLevelInfo.questLevel then
                        questText = string.format("[%d] %s", questLevelInfo.questLevel, questText)
                    end
                    
                    -- Only show coordinates if the quest is available AND player can do it
                    if status == "available" and not isUnavailableToPlayer then
                        local x, y, zoneId = self:GetQuestStarterCoords(chainQuest.id)
                        if x and y and zoneId then
                            -- Always store coordinates for waypoint
                            coordX, coordY, coordZone = x, y, zoneId
                            
                            -- Always show zone name with coordinates
                            local zoneName = self:GetZoneName(zoneId)
                            if zoneName then
                                questText = string.format("%s [%.1f, %.1f] (%s)", questText, x, y, zoneName)
                            else
                                questText = string.format("%s [%.1f, %.1f]", questText, x, y)
                            end
                        else
                            questText = string.format("%s (item)", questText)
                        end
                    end
                    
                    chainLabel:SetText(prefix .. questText)
                    chainLabel:SetFullWidth(true)
                    
                    -- Color based on status and availability
                    if status == "completed" then
                        chainLabel:SetColor(0.6, 0.6, 0.6) -- Light gray
                    elseif status == "accepted" then
                        chainLabel:SetColor(0, 1, 0) -- Green
                    elseif status == "available" and not isUnavailableToPlayer then
                        chainLabel:SetColor(1, 1, 0) -- Yellow (only if player can do it)
                    else -- unavailable or wrong faction/level
                        chainLabel:SetColor(0.8, 0.4, 0.4) -- Muted red
                    end
                    
                    -- Make label clickable - waypoint or wowhead
                    local labelFrame = chainLabel.frame
                    if labelFrame then
                        labelFrame:EnableMouse(true)
                        labelFrame:SetScript("OnMouseDown", function(frame, button)
                            if button == "LeftButton" then
                                if coordX and coordY and coordZone then
                                    self:AddTomTomWaypoint(coordX, coordY, coordZone, chainQuest.name)
                                end
                            elseif button == "RightButton" then
                                -- Show copyable wowhead link popup
                                local url = string.format("https://www.wowhead.com/wotlk/quest=%d", chainQuest.id)
                                self:ShowCopyableURL(url)
                            end
                        end)
                        labelFrame:SetScript("OnEnter", function(frame)
                            local label = frame:GetChildren()
                            if label then
                                label:SetAlpha(0.7)
                            end
                        end)
                        labelFrame:SetScript("OnLeave", function(frame)
                            local label = frame:GetChildren()
                            if label then
                                label:SetAlpha(1.0)
                            end
                        end)
                    end
                    
                    self.scroll:AddChild(chainLabel)
                    
                    -- Show rewards if this quest has any
                    local rewards = chainRewards[chainQuest.id]
                    if rewards and #rewards > 0 then
                        local rewardGroup = AceGUI:Create("SimpleGroup")
                        rewardGroup:SetLayout("Flow")
                        rewardGroup:SetFullWidth(true)
                        
                        for _, reward in ipairs(rewards) do
                            if self:IsRewardItemEligible(reward.id) then
                                local itemIcon = AceGUI:Create("Icon")
                                local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfoCustom(reward.id)
                            
                            if itemTexture then
                                itemIcon:SetImage(itemTexture)
                                itemIcon:SetImageSize(16, 16)
                                itemIcon:SetWidth(24)
                                
                                -- Hover shows tooltip (for already cached items)
                                itemIcon:SetCallback("OnEnter", function(widget)
                                    GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                                    GameTooltip:SetHyperlink("item:" .. reward.id)
                                    GameTooltip:Show()
                                end)
                                
                                itemIcon:SetCallback("OnLeave", function()
                                    GameTooltip:Hide()
                                end)
                                
                                -- Click for item ref
                                itemIcon:SetCallback("OnClick", function(widget, _, button)
                                    if itemLink then
                                        SetItemRef("item:" .. reward.id, itemLink, button)
                                    end
                                end)
                            else
                                -- Loading placeholder
                                itemIcon:SetImage("Interface\\Icons\\INV_Misc_QuestionMark")
                                itemIcon:SetImageSize(16, 16)
                                itemIcon:SetWidth(24)
                                
                                -- Set up a timer to check when item gets cached
                                local checkTimer
                                local function checkItemCached()
                                    local _, _, _, _, _, _, _, _, _, newTexture = GetItemInfo(reward.id)
                                    if newTexture then
                                        itemIcon:SetImage(newTexture)
                                        if checkTimer then
                                            self:CancelTimer(checkTimer)
                                            checkTimer = nil
                                        end
                                    end
                                end
                                
                                -- Start checking when hover triggers caching
                                itemIcon:SetCallback("OnEnter", function(widget)
                                    GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
                                    GameTooltip:SetHyperlink("item:" .. reward.id)
                                    GameTooltip:Show()
                                    
                                    -- Start periodic check for cache update
                                    if not checkTimer then
                                        checkTimer = self:ScheduleRepeatingTimer(checkItemCached, 0.1)
                                    end
                                end)
                                
                                itemIcon:SetCallback("OnLeave", function()
                                    GameTooltip:Hide()
                                end)
                                
                                -- Click for item ref
                                itemIcon:SetCallback("OnClick", function(widget, _, button)
                                    local _, link = GetItemInfo(reward.id)
                                    if link then
                                        SetItemRef("item:" .. reward.id, link, button)
                                    end
                                end)
                            end
                            
                                rewardGroup:AddChild(itemIcon)
                            end
                        end
                        
                        self.scroll:AddChild(rewardGroup)
                    end
                end
            end
            
            -- Add spacing between chains (only if we displayed the header)
            local spacer = AceGUI:Create("Label")
            spacer:SetText(" ")
            spacer:SetFullWidth(true)
            self.scroll:AddChild(spacer)
            end -- end hasVisibleQuests check
        end -- end filter check (showWrongFaction/showLevelTooLow)
        end -- end if IsQuestReal
    end
end
