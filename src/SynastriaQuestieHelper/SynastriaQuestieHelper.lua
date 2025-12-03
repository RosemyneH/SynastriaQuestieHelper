local addonName, addonTable = ...
local SynastriaQuestieHelper = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local SynastriaCoreLib = LibStub("SynastriaCoreLib-1.0", true)

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

function SynastriaQuestieHelper:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("SynastriaQuestieHelperDB", {
        profile = {
            hideCompleted = true, -- Hide completed quests by default
            showWrongFaction = false, -- Show quests for other faction
            showLevelTooLow = false, -- Show quests where player is below required level
            showCrossZoneChains = true, -- Show quest chains that span multiple zones
            persistWaypoints = false, -- Save waypoints between sessions
            framePos = {}, -- Store frame position and size
            minimapButton = {
                hide = false,
                position = 225,
            },
        },
    }, true)

    self:RegisterChatCommand("synastriaquestiehelper", "OnSlashCommand")
    
    -- Setup options
    self:SetupOptions()

    -- Create minimap button
    self:CreateMinimapButton()
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
                        name = "Show Quests You Can't Accept",
                        desc = "Show quests where your level is below the minimum required level to accept them",
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
end

function SynastriaQuestieHelper:OnSlashCommand(input)
    if input:trim() == "toggle" then
        self:ToggleUI()
    elseif input:trim() == "reset" then
        self:ResetFramePosition()
    else
        self:Print("Usage: /synastriaquestiehelper [toggle, reset]")
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
    if self.ZoneDB and self.ZoneDB.private and self.ZoneDB.private.areaIdToUiMapId and self.C_Map then
        for areaId, uiMapId in pairs(self.ZoneDB.private.areaIdToUiMapId) do
            local mapInfo = self.C_Map.GetMapInfo(uiMapId)
            if mapInfo and mapInfo.name == zoneName then
                zoneId = areaId
                break
            end
        end
    end
    
    if not zoneId then
        self:Print(string.format("Could not find AreaId for zone: %s", zoneName))
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
        return false
    end
    
    -- Check quest flags for UNAVAILABLE flag (bit 14 = 16384)
    local questFlags = self.QuestieDB.QueryQuestSingle(questId, "questFlags")
    if questFlags then
        local QUEST_FLAGS_UNAVAILABLE = 16384
        if bit.band(questFlags, QUEST_FLAGS_UNAVAILABLE) ~= 0 then
            return false
        end
    end
    
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
    local questsWithChains = {} -- Track which quests belong in this zone (including chain members)
    
    -- Iterate through all quests in Questie's database
    for questId, _ in pairs(self.QuestieDB.QuestPointers) do
        checkedCount = checkedCount + 1
        
        -- Skip beta/test/unavailable quests
        if not self:IsQuestReal(questId) then
            -- Skip this quest
        else
            -- Check if this quest has attunement rewards
            local itemDBRewards = self:GetQuestRewardsFromItemDB(questId)
            
            if itemDBRewards and #itemDBRewards > 0 then
                local questData = self.QuestieDB.GetQuest(questId)
                
                if questData and questData.name then
                    -- Check if this quest or any quest in its chain is in the current zone
                    local shouldInclude = false
                    local questZone = nil
                    
                    -- Get this quest's zone
                    if questData.zoneOrSort and questData.zoneOrSort > 0 then
                        questZone = questData.zoneOrSort
                    else
                        -- Fallback to starter location zone
                        local x, y, starterZoneId = self:GetQuestStarterCoords(questId)
                        if starterZoneId then
                            questZone = starterZoneId
                        end
                    end
                    
                    -- If this quest is in the current zone, include it
                    if questZone == zoneId then
                        shouldInclude = true
                    elseif self.db.profile.showCrossZoneChains then
                        -- Only check chain if cross-zone chains are enabled
                        -- Check if any quest in the chain is in the current zone
                        local chain = self:GetQuestChain(questId)
                        for _, chainQuest in ipairs(chain) do
                            local chainQuestData = self.QuestieDB.GetQuest(chainQuest.id)
                            if chainQuestData then
                                local chainZone = nil
                                if chainQuestData.zoneOrSort and chainQuestData.zoneOrSort > 0 then
                                    chainZone = chainQuestData.zoneOrSort
                                else
                                    local x, y, starterZoneId = self:GetQuestStarterCoords(chainQuest.id)
                                    if starterZoneId then
                                        chainZone = starterZoneId
                                    end
                                end
                                
                                if chainZone == zoneId then
                                    shouldInclude = true
                                    break
                                end
                            end
                        end
                    end
                    
                    if shouldInclude then
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
        if SynastriaCoreLib and SynastriaCoreLib.IsAttunable(itemId) then
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

-- Get quest starter coordinates from Questie
function SynastriaQuestieHelper:GetQuestStarterCoords(questId)
    if not self.QuestieDB then return nil end
    
    -- Check cache first
    if self.coordCache[questId] ~= nil then
        local cached = self.coordCache[questId]
        if cached then
            return cached.x, cached.y, cached.zoneId
        else
            return nil -- Cached negative result
        end
    end
    
    -- Check NPCs first
    if self.QuestieDB.NPCPointers then
        for npcId in pairs(self.QuestieDB.NPCPointers) do
            local npcData = self.QuestieDB.QueryNPCSingle(npcId, "questStarts")
            if npcData and type(npcData) == "table" then
                -- Check if this NPC starts our quest
                for _, qId in ipairs(npcData) do
                    if qId == questId then
                        -- Found NPC that starts this quest, get spawns
                        local spawns = self.QuestieDB.QueryNPCSingle(npcId, "spawns")
                        if spawns and type(spawns) == "table" then
                            -- spawns is {[zoneId] = {{x,y}, {x,y}}}
                            for zoneId, coords in pairs(spawns) do
                                if coords and coords[1] and coords[1][1] and coords[1][2] then
                                    -- Cache the result
                                    self.coordCache[questId] = {x = coords[1][1], y = coords[1][2], zoneId = zoneId}
                                    return coords[1][1], coords[1][2], zoneId
                                end
                            end
                        end
                        break
                    end
                end
            end
        end
    end
    
    -- Check Objects if no NPC found
    if self.QuestieDB.ObjectPointers then
        for objId in pairs(self.QuestieDB.ObjectPointers) do
            local objData = self.QuestieDB.QueryObjectSingle(objId, "questStarts")
            if objData and type(objData) == "table" then
                -- Check if this object starts our quest
                for _, qId in ipairs(objData) do
                    if qId == questId then
                        -- Found object that starts this quest, get spawns
                        local spawns = self.QuestieDB.QueryObjectSingle(objId, "spawns")
                        if spawns and type(spawns) == "table" then
                            -- spawns is {[zoneId] = {{x,y}, {x,y}}}
                            for zoneId, coords in pairs(spawns) do
                                if coords and coords[1] and coords[1][1] and coords[1][2] then
                                    -- Cache the result
                                    self.coordCache[questId] = {x = coords[1][1], y = coords[1][2], zoneId = zoneId}
                                    return coords[1][1], coords[1][2], zoneId
                                end
                            end
                        end
                        break
                    end
                end
            end
        end
    end
    
    -- Cache nil result to avoid repeated lookups
    self.coordCache[questId] = false
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
    
    -- Cache the result
    self.chainCache[questId] = chain
    
    return chain
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
    tinsert(UISpecialFrames, "SynastriaQuestieHelperMainFrame")
    
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
                        local itemId = tonumber(itemLink:match("item:(%d+)"))
                        if itemId and SynastriaCoreLib and SynastriaCoreLib.IsAttunable(itemId) then
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
                        local itemId = tonumber(itemLink:match("item:(%d+)"))
                        if itemId and SynastriaCoreLib and SynastriaCoreLib.IsAttunable(itemId) then
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
    if not requiredRaces or requiredRaces == 0 then
        return true -- No race restriction
    end
    
    -- Get player's race
    local _, playerRace = UnitRace("player")
    if not playerRace then return true end
    
    -- Lazy-load race keys from QuestieDB
    if not self.raceKeys and self.QuestieDB and self.QuestieDB.raceKeys then
        self.raceKeys = self.QuestieDB.raceKeys
    end
    
    if not self.raceKeys then return true end
    
    -- Map player race to bitmask
    local raceMask = self.raceKeys[string.upper(playerRace)]
    if not raceMask then return true end
    
    -- Check if player's race is in the bitmask
    return bit.band(requiredRaces, raceMask) ~= 0
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
                            local itemIcon = AceGUI:Create("Icon")
                            local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(reward.id)
                            
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
                        
                        self.scroll:AddChild(rewardGroup)
                    end
                end
            end
            
            -- Add spacing between chains
            local spacer = AceGUI:Create("Label")
            spacer:SetText(" ")
            spacer:SetFullWidth(true)
            self.scroll:AddChild(spacer)
        end -- end filter check (showWrongFaction/showHighLevel)
        end -- end if IsQuestReal
    end
end
