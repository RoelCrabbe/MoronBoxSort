------------------------------------------------------------------------------------------------------
------------------------------------------------ FRAME! ----------------------------------------------
------------------------------------------------------------------------------------------------------

local MoronSortEvent = CreateFrame("Button", "MoronSortEvent", UIParent)
local MoronSortUpdate = CreateFrame("Button", "MoronSortUpdate", UIParent)
local MoronSortTooltip = CreateFrame("GameTooltip", "MoronSortTooltip", UIParent, "GameTooltipTemplate")

MoronSortUpdate:Hide()

------------------------------------------------------------------------------------------------------
----------------------------------------------- Locals! ----------------------------------------------
------------------------------------------------------------------------------------------------------

local BagNumbers
local model, itemStacks, itemClasses, itemSortKeys

local timeOut
local timeDelay = 0

local _, _, _, hasMoronBoxCore, _, _, _ = GetAddOnInfo("MoronBoxCore")

------------------------------------------------------------------------------------------------------
--------------------------------------------- OnUpdate! ----------------------------------------------
------------------------------------------------------------------------------------------------------

do
	for _, event in {
		"MERCHANT_SHOW", 
		"BANKFRAME_OPENED",
		"BAG_UPDATE"
		} 
		do MoronSortEvent:RegisterEvent(event)
	end
end

function MoronSortEvent:OnEvent()

	if (event == "MERCHANT_SHOW" or event == "BANKFRAME_OPENED") then

		if hasMoronBoxCore and MB_sortingBags.Active then

			mb_sortBags()

			if MB_sortingBags.Bank then
			
				mb_sortBankBags()
			end
		end
	end
end

MoronSortEvent:SetScript("OnEvent", MoronSortEvent.OnEvent) 

function MoronSortUpdate:OnUpdate()
	timeDelay = timeDelay - arg1

	if timeDelay <= 0 then
		timeDelay = 0.2

		local finishedSort = Sort()

		if finishedSort or GetTime() > timeOut then
			MoronSortUpdate:Hide()
			return
		end

		Stack()
	end
end

MoronSortUpdate:SetScript("OnUpdate", MoronSortUpdate.OnUpdate)

------------------------------------------------------------------------------------------------------
--------------------------------------- Raid Assistance Tools! ---------------------------------------
------------------------------------------------------------------------------------------------------

function mb_sortBags()
	BagNumbers = {0, 1, 2, 3, 4}
	Start()
end

function mb_sortBankBags()
	BagNumbers = {-1, 5, 6, 7, 8, 9, 10}
	Start()
end

function Start()
	if MoronSortUpdate:IsShown() then return end
	Initialize()
	timeOut = GetTime() + 7
	MoronSortUpdate:Show()
end

do
	local function key(table, value)
		for k, v in table do
			if v == value then
				return k
			end
		end
	end

	function ItemTypeKey(itemClass)
		return key(ITEM_TYPES, itemClass) or 0
	end

	function ItemSubTypeKey(itemClass, itemSubClass)
		return key({GetAuctionItemSubClasses(ItemTypeKey(itemClass))}, itemClass) or 0
	end

	function ItemInvTypeKey(itemClass, itemSubClass, itemSlot)
		return key({GetAuctionInvTypes(ItemTypeKey(itemClass), ItemSubTypeKey(itemSubClass))}, itemSlot) or 0
	end
end

function LT(a, b)
	local i = 1
	while true do
		if a[i] and b[i] and a[i] ~= b[i] then
			return a[i] < b[i]
		elseif not a[i] and b[i] then
			return true
		elseif not b[i] then
			return false
		end
		i = i + 1
	end
end

function Move(src, dst)
    local texture, _, srcLocked = GetContainerItemInfo(src.container, src.position)
    local _, _, dstLocked = GetContainerItemInfo(dst.container, dst.position)
    
	if texture and not srcLocked and not dstLocked then
		ClearCursor()
       	PickupContainerItem(src.container, src.position)
		PickupContainerItem(dst.container, dst.position)

		if src.item == dst.item then
			local count = min(src.count, itemStacks[dst.item] - dst.count)
			src.count = src.count - count
			dst.count = dst.count + count
			if src.count == 0 then
				src.item = nil
			end
		else
			src.item, dst.item = dst.item, src.item
			src.count, dst.count = dst.count, src.count
		end

		return true
    end
end

function TooltipInfo(container, position)
	local chargesPattern = '^' .. gsub(gsub(ITEM_SPELL_CHARGES_P1, '%%d', '(%%d+)'), '%%%d+%$d', '(%%d+)') .. '$'

	MoronSortTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	MoronSortTooltip:ClearLines()

	if container == BANK_CONTAINER then
		MoronSortTooltip:SetInventoryItem('player', BankButtonIDToInvSlotID(position))
	else
		MoronSortTooltip:SetBagItem(container, position)
	end

	local charges, usable, soulbound, quest, conjured
	for i = 1, MoronSortTooltip:NumLines() do
		local text = getglobal('MoronSortTooltipTextLeft' .. i):GetText()

		local _, _, chargeString = strfind(text, chargesPattern)
		if chargeString then
			charges = tonumber(chargeString)
		elseif strfind(text, '^' .. ITEM_SPELL_TRIGGER_ONUSE) then
			usable = true
		elseif text == ITEM_SOULBOUND then
			soulbound = true
		elseif text == ITEM_BIND_QUEST then
			quest = true
		elseif text == ITEM_CONJURED then
			conjured = true
		end
	end

	return charges or 1, usable, soulbound, quest, conjured
end

function Sort()
	local complete = true

	for _, dst in model do
		if dst.targetItem and (dst.item ~= dst.targetItem or dst.count < dst.targetCount) then
			complete = false

			local sources, rank = {}, {}

			for _, src in model do
				if src.item == dst.targetItem
					and src ~= dst
					and not (dst.item and src.class and src.class ~= itemClasses[dst.item])
					and not (src.targetItem and src.item == src.targetItem and src.count <= src.targetCount)
				then
					rank[src] = abs(src.count - dst.targetCount + (dst.item == dst.targetItem and dst.count or 0))
					tinsert(sources, src)
				end
			end

			sort(sources, function(a, b) return rank[a] < rank[b] end)

			for _, src in sources do
				if Move(src, dst) then
					break
				end
			end
		end
	end

	return complete
end

function Stack()
	for _, src in model do
		if src.item and src.count < itemStacks[src.item] and src.item ~= src.targetItem then
			for _, dst in model do
				if dst ~= src and dst.item and dst.item == src.item and dst.count < itemStacks[dst.item] and dst.item ~= dst.targetItem then
					Move(src, dst)
				end
			end
		end
	end
end

do
	local counts

	local function insert(t, v)
		tinsert(t, 1, v)
	end

	local function assign(slot, item)
		if counts[item] > 0 then
			local count

				count = min(counts[item], itemStacks[item])
			
			slot.targetItem = item
			slot.targetCount = count
			counts[item] = counts[item] - count
			return true
		end
	end

	function Initialize()
		model, counts, itemStacks, itemClasses, itemSortKeys = {}, {}, {}, {}, {}

		for _, container in BagNumbers do
			local class = ContainerClass(container)
			for position = 1, GetContainerNumSlots(container) do
				local slot = {container=container, position=position, class=class}
				local item = Item(container, position)
				if item then
					local _, count = GetContainerItemInfo(container, position)
					slot.item = item
					slot.count = count
					counts[item] = (counts[item] or 0) + count
				end
				insert(model, slot)
			end
		end

		local free = {}
		for item, count in counts do
			local stacks = ceil(count / itemStacks[item])
			free[item] = stacks
			if itemClasses[item] then
				free[itemClasses[item]] = (free[itemClasses[item]] or 0) + stacks
			end
		end
		for _, slot in model do
			if slot.class and free[slot.class] then
				free[slot.class] = free[slot.class] - 1
			end
		end

		local items = {}
		for item in counts do
			tinsert(items, item)
		end
		sort(items, function(a, b) return LT(itemSortKeys[a], itemSortKeys[b]) end)

		for _, slot in model do
			if slot.class then
				for _, item in items do
					if itemClasses[item] == slot.class and assign(slot, item) then
						break
					end
				end
			else
				for _, item in items do
					if (not itemClasses[item] or free[itemClasses[item]] > 0) and assign(slot, item) then
						if itemClasses[item] then
							free[itemClasses[item]] = free[itemClasses[item]] - 1
						end
						break
					end
				end
			end
		end
	end
end

function ContainerClass(container)
	if container ~= 0 and container ~= BANK_CONTAINER then
		local name = GetBagName(container)
		if name then		
			for class, info in CLASSES do
				for _, itemID in info.BagNumbers do
					if name == GetItemInfo(itemID) then
						return class
					end
				end	
			end
		end
	end
end

function Item(container, position)
	local link = GetContainerItemLink(container, position)
	if link then
		local _, _, itemID, enchantID, suffixID, uniqueID = strfind(link, 'item:(%d+):(%d*):(%d*):(%d*)')
		itemID = tonumber(itemID)
		local _, _, quality, _, type, subType, stack, invType = GetItemInfo(itemID)
		local charges, usable, soulbound, quest, conjured = TooltipInfo(container, position)

		local sortKey = {}

		-- hearthstone
		if itemID == 6948 then
			tinsert(sortKey, 1)

		-- mounts
		elseif MOUNTS[itemID] then
			tinsert(sortKey, 2)

		-- special items
		elseif SPECIAL[itemID] then
			tinsert(sortKey, 3)

		-- key items
		elseif KEYS[itemID] then
			tinsert(sortKey, 4)

		-- tools
		elseif TOOLS[itemID] then
			tinsert(sortKey, 5)

		-- soul shards
		elseif itemID == 6265 then
			tinsert(sortKey, 20)

		-- conjured items
		elseif conjured then
			tinsert(sortKey, 21)

		elseif JUJU[itemID] then
			tinsert(sortKey, 6)

		-- soulbound items
		elseif soulbound then
			tinsert(sortKey, 12)

		-- reagents
		elseif type == ITEM_TYPES[9] then
			tinsert(sortKey, 13)

		-- quest items
		elseif quest then
			tinsert(sortKey, 15)

		-- consumables
		elseif usable and type ~= ITEM_TYPES[1] and type ~= ITEM_TYPES[2] and type ~= ITEM_TYPES[8] or type == ITEM_TYPES[4] then
			tinsert(sortKey, 14)

		-- enchanting materials
		elseif ENCHANTING_MATERIALS[itemID] then
			tinsert(sortKey, 16)

		-- herbs
		elseif HERBS[itemID] then
			tinsert(sortKey, 18)

		-- higher quality
		elseif quality > 1 then
			tinsert(sortKey, 16)

		-- common quality
		elseif quality == 1 then
			tinsert(sortKey, 19)

		-- junk
		elseif quality == 0 then
			tinsert(sortKey, 20)
		end
		
		tinsert(sortKey, ItemTypeKey(type))
		tinsert(sortKey, ItemInvTypeKey(type, subType, invType))
		tinsert(sortKey, ItemSubTypeKey(type, subType))
		tinsert(sortKey, -quality)
		tinsert(sortKey, itemID)
		tinsert(sortKey, suffixID)
		tinsert(sortKey, enchantID)
		tinsert(sortKey, uniqueID)

		local key = format('%s:%s:%s:%s:%s:%s', itemID, enchantID, suffixID, uniqueID, charges, (soulbound and 1 or 0))

		itemStacks[key] = stack
		itemSortKeys[key] = sortKey

		for class, info in CLASSES do
			if info.items[itemID] then
				itemClasses[key] = class
				break
			end
		end

		return key
	end
end
