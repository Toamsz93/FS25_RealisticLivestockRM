--[[
    RLMenuInfoFrame.lua
    RL Tabbed Menu - Info tab (Phase 2a).

    Left-sidebar husbandry picker with dot indicators, multi-section
    SmoothList of animal cards per husbandry. Pure read in Phase 2a;
    Phase 2b adds the right-hand detail pane and tier-A mutations.
]]

RLMenuInfoFrame = {}
local RLMenuInfoFrame_mt = Class(RLMenuInfoFrame, TabbedMenuFrameElement)

local Log = RmLogging.getLogger("RLRM")

local modDirectory = g_currentModDirectory

---Construct a new RLMenuInfoFrame instance. Called once by setupGui.
---@return table self
function RLMenuInfoFrame.new()
    local self = RLMenuInfoFrame:superClass().new(nil, RLMenuInfoFrame_mt)
    self.name = "RLMenuInfoFrame"

    self.sortedHusbandries = {}
    self.selectedHusbandry = nil
    self.items             = {}
    self.filters           = {}
    self.farmId            = nil

    self.sectionOrder      = {}
    self.itemsBySection    = {}
    self.titlesBySection   = {}

    self.selectedIdentity  = nil  -- { farmId, uniqueId, country }

    -- Track husbandry's animal type so we can clear filters on type change
    -- (cow filters reference fields a sheep doesn't have and would drop every row).
    self.activeAnimalTypeIndex = nil

    self.isFrameOpen = false

    self.hasCustomMenuButtons = true
    self.backButtonInfo = { inputAction = InputAction.MENU_BACK }
    self.filterButtonInfo = {
        inputAction = InputAction.MENU_CANCEL,
        text = g_i18n:getText("rl_menu_info_filter_button"),
        callback = function() self:onClickFilter() end,
    }
    self.menuButtonInfo = { self.backButtonInfo }

    return self
end

---Load the info frame XML and register it with g_gui so the host menu's
---FrameReference can resolve it.
function RLMenuInfoFrame.setupGui()
    local frame = RLMenuInfoFrame.new()
    g_gui:loadGui(
        Utils.getFilename("gui/rlmenu/infoFrame.xml", modDirectory),
        "RLMenuInfoFrame",
        frame,
        true
    )
    Log:debug("RLMenuInfoFrame.setupGui: registered")
end

--- Bind the SmoothList datasource/delegate. Must not mutate the element
--- tree here: this hook fires on both the frame-only load instance AND
--- the clone resolveFrameReference creates, and tree mutation on the
--- first instance leaves the clone without what it needs. Tree mutation
--- lives in `initialize()` below, called by the host menu on the clone.
function RLMenuInfoFrame:onGuiSetupFinished()
    RLMenuInfoFrame:superClass().onGuiSetupFinished(self)

    if self.animalList ~= nil then
        self.animalList:setDataSource(self)
        self.animalList:setDelegate(self)
    else
        Log:warning("RLMenuInfoFrame:onGuiSetupFinished: animalList element missing from XML")
    end
end

--- One-time per-clone setup. Called explicitly by RLMenu:setupMenuPages
--- after the page is registered.
function RLMenuInfoFrame:initialize()
    if self.subCategoryDotTemplate ~= nil then
        self.subCategoryDotTemplate:unlinkElement()
        FocusManager:removeElement(self.subCategoryDotTemplate)
    else
        Log:warning("RLMenuInfoFrame:initialize: subCategoryDotTemplate missing - dots will not render")
    end
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

---Called by the Paging element when this tab becomes active.
function RLMenuInfoFrame:onFrameOpen()
    RLMenuInfoFrame:superClass().onFrameOpen(self)
    self.isFrameOpen = true
    self:refreshHusbandries()
end

---Called by the Paging element when this tab is deactivated.
function RLMenuInfoFrame:onFrameClose()
    RLMenuInfoFrame:superClass().onFrameClose(self)
    self.isFrameOpen = false
end

-- =============================================================================
-- Husbandry selector
-- =============================================================================

--- Repopulate the husbandry selector + dot indicators for the player's farm.
function RLMenuInfoFrame:refreshHusbandries()
    local farmId
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        farmId = g_currentMission:getFarmId()
    end
    self.farmId = farmId

    self.sortedHusbandries = RLAnimalQuery.listHusbandriesForFarm(farmId)
    Log:debug("RLMenuInfoFrame:refreshHusbandries: farmId=%s husbandries=%d",
        tostring(farmId), #self.sortedHusbandries)

    if self.subCategoryDotBox ~= nil then
        for i, dot in pairs(self.subCategoryDotBox.elements) do
            dot:delete()
            self.subCategoryDotBox.elements[i] = nil
        end
    end

    if #self.sortedHusbandries == 0 then
        if self.noHusbandriesText ~= nil then self.noHusbandriesText:setVisible(true) end
        if self.subCategoryDotBox ~= nil then self.subCategoryDotBox:setVisible(false) end
        if self.subCategorySelector ~= nil then self.subCategorySelector:setTexts({}) end
        self.selectedHusbandry = nil
        self.items = {}
        if self.animalList ~= nil then self.animalList:reloadData() end
        self:updateEmptyState()
        self:updateButtonVisibility()
        return
    end

    if self.noHusbandriesText ~= nil then self.noHusbandriesText:setVisible(false) end

    local names = {}
    for index, husbandry in ipairs(self.sortedHusbandries) do
        names[index] = RLAnimalQuery.formatHusbandryLabel(husbandry, index)

        if self.subCategoryDotTemplate ~= nil and self.subCategoryDotBox ~= nil then
            local dot = self.subCategoryDotTemplate:clone(self.subCategoryDotBox)
            local dotIndex = index
            function dot.getIsSelected()
                return self.subCategorySelector ~= nil
                    and self.subCategorySelector:getState() == dotIndex
            end
        end
    end

    if self.subCategoryDotBox ~= nil then
        self.subCategoryDotBox:invalidateLayout()
        self.subCategoryDotBox:setVisible(1 < #names)
    end

    if self.subCategorySelector ~= nil then
        self.subCategorySelector:setTexts(names)
        self.subCategorySelector:setState(1, true)
    else
        self:onHusbandryChanged(1)
    end
end

--- MultiTextOption onClick callback. Clears filters on animal-type change
--- so filter fields from the previous type can't reference missing data.
--- @param state number 1-based husbandry index
function RLMenuInfoFrame:onHusbandryChanged(state)
    if state == nil or state < 1 or state > #self.sortedHusbandries then return end

    self.selectedHusbandry = self.sortedHusbandries[state]
    local newTypeIndex
    if self.selectedHusbandry ~= nil and self.selectedHusbandry.getAnimalTypeIndex ~= nil then
        newTypeIndex = self.selectedHusbandry:getAnimalTypeIndex()
    end

    if self.activeAnimalTypeIndex ~= nil
        and newTypeIndex ~= nil
        and newTypeIndex ~= self.activeAnimalTypeIndex
        and next(self.filters) ~= nil then
        Log:debug("RLMenuInfoFrame:onHusbandryChanged: animal type changed (%s -> %s), clearing filters",
            tostring(self.activeAnimalTypeIndex), tostring(newTypeIndex))
        self.filters = {}
    end
    self.activeAnimalTypeIndex = newTypeIndex

    Log:debug("RLMenuInfoFrame:onHusbandryChanged: state=%d husbandry='%s'",
        state,
        (self.selectedHusbandry ~= nil and self.selectedHusbandry.getName ~= nil
            and self.selectedHusbandry:getName()) or "?")

    self:reloadAnimalList()
end

-- =============================================================================
-- Animal list
-- =============================================================================

--- Requery the current husbandry, group into sections, refresh the SmoothList,
--- restore selection by (farmId, uniqueId, country) identity.
function RLMenuInfoFrame:reloadAnimalList()
    self:captureCurrentSelection()

    if self.selectedHusbandry == nil then
        self.items = {}
    else
        self.items = RLAnimalQuery.listAnimalsForHusbandry(self.selectedHusbandry, self.filters)
    end

    self.sectionOrder, self.itemsBySection, self.titlesBySection =
        RLAnimalQuery.buildSections(self.items)

    if self.animalList ~= nil then
        self.animalList:reloadData()
    end

    self:restoreSelection()
    self:updateEmptyState()
    self:updateButtonVisibility()
end

--- Capture the currently highlighted animal's identity so it can be re-selected
--- after the next reload.
function RLMenuInfoFrame:captureCurrentSelection()
    if self.animalList == nil then return end
    local section = self.animalList.selectedSectionIndex
    local index   = self.animalList.selectedIndex
    if section == nil or index == nil then return end

    local key = self.sectionOrder[section]
    if key == nil then return end
    local list = self.itemsBySection[key]
    if list == nil or index < 1 or index > #list then return end

    local item = list[index]
    if item == nil or item.cluster == nil then return end

    local cluster = item.cluster
    local country = ""
    if cluster.birthday ~= nil then country = cluster.birthday.country or "" end
    self.selectedIdentity = {
        farmId   = cluster.farmId or 0,
        uniqueId = cluster.uniqueId or 0,
        country  = country,
    }
end

--- Re-highlight the previously selected animal. Falls back to (1, 1) when
--- the previous animal is no longer present.
function RLMenuInfoFrame:restoreSelection()
    if self.animalList == nil then return end

    if #self.sectionOrder == 0 then
        self.selectedIdentity = nil
        return
    end

    local section, index
    if self.selectedIdentity ~= nil then
        section, index = RLAnimalQuery.findSectionedItemByIdentity(
            self.sectionOrder,
            self.itemsBySection,
            self.selectedIdentity.farmId,
            self.selectedIdentity.uniqueId,
            self.selectedIdentity.country
        )
    end

    if section == nil or index == nil then
        section, index = 1, 1
    end

    self.animalList:setSelectedItem(section, index, false, true)
end

-- =============================================================================
-- Empty state / buttons
-- =============================================================================

---Toggle empty-state text + list chrome based on the current data.
function RLMenuInfoFrame:updateEmptyState()
    local hasHusbandries = #self.sortedHusbandries > 0
    local hasItems = #self.items > 0

    if self.noAnimalsText ~= nil then
        self.noAnimalsText:setVisible(hasHusbandries and not hasItems)
    end
    if self.noHusbandriesText ~= nil then
        self.noHusbandriesText:setVisible(not hasHusbandries)
    end
    if self.animalList ~= nil then
        self.animalList:setVisible(hasItems)
    end
end

---Rebuild the footer button info. Back is always shown; Filter only when
---at least one husbandry is available to filter.
function RLMenuInfoFrame:updateButtonVisibility()
    self.menuButtonInfo = { self.backButtonInfo }
    if #self.sortedHusbandries > 0 then
        table.insert(self.menuButtonInfo, self.filterButtonInfo)
    end
    self:setMenuButtonInfoDirty()
end

-- =============================================================================
-- Filter button
-- =============================================================================

---Open AnimalFilterDialog for the current husbandry's animals.
function RLMenuInfoFrame:onClickFilter()
    if self.selectedHusbandry == nil then return end
    if AnimalFilterDialog == nil or AnimalFilterDialog.show == nil then
        Log:warning("RLMenuInfoFrame:onClickFilter: AnimalFilterDialog unavailable")
        return
    end

    local animalTypeIndex
    if self.selectedHusbandry.getAnimalTypeIndex ~= nil then
        animalTypeIndex = self.selectedHusbandry:getAnimalTypeIndex()
    end

    Log:debug("RLMenuInfoFrame:onClickFilter: opening dialog for %d items, animalTypeIndex=%s",
        #self.items, tostring(animalTypeIndex))

    AnimalFilterDialog.show(self.items, animalTypeIndex, self.onFilterApplied, self, false)
end

---AnimalFilterDialog callback fired on OK. Stores filters and re-queries.
---@param filters table
---@param _items table unused; we re-query via reloadAnimalList
function RLMenuInfoFrame:onFilterApplied(filters, _items)
    Log:debug("RLMenuInfoFrame:onFilterApplied: %d filter(s) active",
        (filters ~= nil and #filters) or 0)
    self.filters = filters or {}
    self:reloadAnimalList()
end

-- =============================================================================
-- SmoothList data source / delegate
-- =============================================================================

---SmoothList data source: number of sections in the list.
---@param list table
---@return number
function RLMenuInfoFrame:getNumberOfSections(list)
    if list == self.animalList then return #self.sectionOrder end
    return 0
end

---SmoothList data source: title for the given section header cell.
---@param list table
---@param section number
---@return string|nil
function RLMenuInfoFrame:getTitleForSectionHeader(list, section)
    if list ~= self.animalList then return nil end
    local key = self.sectionOrder[section]
    return key and self.titlesBySection[key] or nil
end

---SmoothList data source: number of items in the given section.
---@param list table
---@param section number
---@return number
function RLMenuInfoFrame:getNumberOfItemsInSection(list, section)
    if list ~= self.animalList then return 0 end
    local key = self.sectionOrder[section]
    if key == nil then return 0 end
    local items = self.itemsBySection[key]
    return items ~= nil and #items or 0
end

---SmoothList delegate: populate one data cell from the item at (section, index).
---@param list table
---@param section number
---@param index number
---@param cell table
function RLMenuInfoFrame:populateCellForItemInSection(list, section, index, cell)
    if list ~= self.animalList then return end

    local key = self.sectionOrder[section]
    if key == nil then return end
    local items = self.itemsBySection[key]
    if items == nil then return end
    local item = items[index]
    if item == nil then return end

    local row = RLAnimalQuery.formatAnimalRow(item)

    -- Cell tint: disease red, marked orange, normal otherwise.
    if cell.setImageColor ~= nil then
        if row.tint == RLAnimalQuery.TINT_DISEASE then
            cell:setImageColor(GuiOverlay.STATE_NORMAL, 1, 0.08, 0)
        elseif row.tint == RLAnimalQuery.TINT_MARKED then
            cell:setImageColor(GuiOverlay.STATE_NORMAL, 1, 0.2, 0)
        else
            cell:setImageColor(GuiOverlay.STATE_NORMAL, 1, 1, 1)
        end
    end

    local iconCell = cell:getAttribute("icon")
    if iconCell ~= nil then
        if row.icon ~= nil then
            iconCell:setImageFilename(row.icon)
            iconCell:setVisible(true)
        else
            iconCell:setVisible(false)
        end
    end

    -- Name split: baseName empty -> show idNoName only; else show id + name.
    local idNoNameCell = cell:getAttribute("idNoName")
    local idCell       = cell:getAttribute("id")
    local nameCell     = cell:getAttribute("name")
    local hasBaseName  = row.baseName ~= ""
    if idNoNameCell ~= nil then
        idNoNameCell:setText(row.displayIdentifier)
        idNoNameCell:setVisible(not hasBaseName)
    end
    if idCell ~= nil then
        idCell:setText(row.identifier)
        idCell:setVisible(hasBaseName)
    end
    if nameCell ~= nil then
        nameCell:setText(row.displayName)
        nameCell:setVisible(hasBaseName)
    end

    local priceCell = cell:getAttribute("price")
    if priceCell ~= nil then
        if priceCell.setValue ~= nil then
            priceCell:setValue(row.price)
        else
            priceCell:setText(tostring(row.price))
        end
    end

    local descriptor = cell:getAttribute("herdsmanPurchase")
    if descriptor ~= nil then
        descriptor:setVisible(row.descriptorVisible)
        if row.descriptorVisible then
            descriptor:setText(row.descriptorText)
        end
    end
end
