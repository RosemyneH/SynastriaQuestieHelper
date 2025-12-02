-- Quest Chain Database (Fallback)
-- This is only used when Questie is not available or missing data.
-- Primary source is Questie addon.
-- Structure: [QuestID] = { name = "Quest Name", preQuest = prerequisiteQuestID }

local _, SynastriaQuestieHelper = ...

SynastriaQuestieHelper.QuestDB = {
    -- Add manual quest chains here only for quests missing from Questie
    -- Example:
    -- [123] = { name = "Quest Name", preQuest = 122 },
}
