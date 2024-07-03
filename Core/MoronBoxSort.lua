------------------------------------------------------------------------------------------------------
------------------------------------------------ FRAME! ----------------------------------------------
------------------------------------------------------------------------------------------------------

local _G, _M = getfenv(0), {}
setfenv(1, setmetatable(_M, {__index=_G}))

local MoronSortEvent = CreateFrame("Button", "MoronSortEvent", UIParent)
local MoronSortUpdate = CreateFrame("Button", "MoronSortUpdate", UIParent)
local MoronSortTooltip = CreateFrame("GameTooltip", "MoronSortTooltip", UIParent, "GameTooltipTemplate")

MoronSortUpdate:Hide()

------------------------------------------------------------------------------------------------------
----------------------------------------------- Locals! ----------------------------------------------
------------------------------------------------------------------------------------------------------

local CONTAINERS
local model, itemStacks, itemClasses, itemSortKeys

local timeOut
local timeDelay = 0
local counts

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

			SortBags()

			if MB_sortingBags.Bank then
			
				SortBankBags()
			end
		end
	end
end

MoronSortEvent:SetScript("OnEvent", MoronSortEvent.OnEvent) 

function MoronSortUpdate:OnUpdate()
	timeDelay = timeDelay - arg1

	if timeDelay <= 0 then
		timeDelay = 0.2

		local finishedSort = SortBag()

		if finishedSort or GetTime() > timeOut then
			MoronSortUpdate:Hide()
			return
		end

		StackItem()
	end
end

MoronSortUpdate:SetScript("OnUpdate", MoronSortUpdate.OnUpdate)

------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------

function _G.SortBags()
	CONTAINERS = {0, 1, 2, 3, 4}
	StartPacking()
end

function _G.SortBankBags()
	CONTAINERS = {-1, 5, 6, 7, 8, 9, 10}
	StartPacking()
end

------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------

function StartPacking()
	if MoronSortUpdate:IsShown() then return end

	model, counts, itemStacks, itemClasses, itemSortKeys = {}, {}, {}, {}, {}
	timeOut = GetTime() + 7
	MoronSortUpdate:Show()

	for _, container in CONTAINERS do
		local class = ContainerClass(container)
		for position = 1, GetContainerNumSlots(container) do
			local slot = {container=container, position=position, class=class}
			local item = BagItem(container, position)
			if item then
				local _, count = GetContainerItemInfo(container, position)
				slot.item = item
				slot.count = count
				counts[item] = (counts[item] or 0) + count
			end
			tinsert(model, 1, slot)
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
				if itemClasses[item] == slot.class and Assign(slot, item) then
					break
				end
			end
		else
			for _, item in items do
				if (not itemClasses[item] or free[itemClasses[item]] > 0) and Assign(slot, item) then
					if itemClasses[item] then
						free[itemClasses[item]] = free[itemClasses[item]] - 1
					end
					break
				end
			end
		end
	end
end

function MoveBagItem(src, dst)
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

function SortBag()
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
				if MoveBagItem(src, dst) then
					break
				end
			end
		end
	end
	return complete
end

function StackItem()
	for _, src in model do
		if src.item and src.count < itemStacks[src.item] and src.item ~= src.targetItem then
			for _, dst in model do
				if dst ~= src and dst.item and dst.item == src.item and dst.count < itemStacks[dst.item] and dst.item ~= dst.targetItem then
					MoveBagItem(src, dst)
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------

function BagItem(container, position)
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

function TableKey(table, value)
	for k, v in table do
		if v == value then
			return k
		end
	end
end

function ItemTypeKey(itemClass)
	return TableKey(ITEM_TYPES, itemClass) or 0
end

function ItemSubTypeKey(itemClass, itemSubClass)
	return TableKey({GetAuctionItemSubClasses(ItemTypeKey(itemClass))}, itemClass) or 0
end

function ItemInvTypeKey(itemClass, itemSubClass, itemSlot)
	return TableKey({GetAuctionInvTypes(ItemTypeKey(itemClass), ItemSubTypeKey(itemSubClass))}, itemSlot) or 0
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

function Assign(slot, item)
	if counts[item] > 0 then
		local count
		count = min(counts[item], itemStacks[item])
		slot.targetItem = item
		slot.targetCount = count
		counts[item] = counts[item] - count
		return true
	end
end

function ContainerClass(container)
	if container ~= 0 and container ~= BANK_CONTAINER then
		local name = GetBagName(container)
		if name then		
			for class, info in CLASSES do
				for _, itemID in info.containers do
					if name == GetItemInfo(itemID) then
						return class
					end
				end	
			end
		end
	end
end

------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------

function Set(...)
	local t = {}
	for i = 1, arg.n do
		t[arg[i]] = true
	end
	return t
end

function Union(...)
	local t = {}
	for i = 1, arg.n do
		for k in arg[i] do
			t[k] = true
		end
	end
	return t
end

------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------

ITEM_TYPES = {GetAuctionItemClasses()}

MOUNTS = Set(
	5864, 5872, 5873, 18785, 18786, 18787, 18244, 19030, 13328, 13329,
	2411, 2414, 5655, 5656, 18778, 18776, 18777, 18241, 12353, 12354,
	8629, 8631, 8632, 18766, 18767, 18902, 18242, 13086, 19902, 12302, 12303, 8628, 12326,
	8563, 8595, 13321, 13322, 18772, 18773, 18774, 18243, 13326, 13327,
	15277, 15290, 18793, 18794, 18795, 18247, 15292, 15293,
	1132, 5665, 5668, 18796, 18797, 18798, 18245, 12330, 12351,
	8588, 8591, 8592, 18788, 18789, 18790, 18246, 19872, 8586, 13317,
	13331, 13332, 13333, 13334, 18791, 18248, 13335,
	21218, 21321, 21323, 21324, 21176
)

SPECIAL = Set(5175, 5176, 5177, 5178, 5462, 17696, 17117, 13347, 13289, 11511, 19017, 18564, 18563, 22754, 19858, 20079, 20081, 20080, 11516, 15138)

KEYS = Set(9240, 17191, 13544, 12324, 16309, 12384, 20402)

TOOLS = Set(7005, 12709, 19727, 5956, 2901, 6219, 10498, 6218, 6339, 11130, 11145, 16207, 9149, 15846, 6256, 6365, 6367, 9149)

JUJU = Set(12457, 12455, 12459, 12450, 12458, 12460, 12451, 13180)

ENCHANTING_MATERIALS = Set(
	10940, 11083, 11137, 11176, 16204,
	10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203,
	10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344,
	20725
)

HERBS = Set(765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369, 3818, 3819, 3820, 3821, 4625, 8153, 8831, 8836, 8838, 8839, 8845, 8846, 13463, 13464, 13465, 13466, 13467, 13468)

SEEDS = Set(17034, 17035, 17036, 17037, 17038)

CLASSES = {
	{
		containers = {2101, 5439, 7278, 11362, 3573, 3605, 7371, 8217, 2662, 19319, 18714},
		items = Set(2512, 2515, 3030, 3464, 9399, 11285, 12654, 18042, 19316),
	},
	{
		containers = {2102, 5441, 7279, 11363, 3574, 3604, 7372, 8218, 2663, 19320},
		items = Set(2516, 2519, 3033, 3465, 4960, 5568, 8067, 8068, 8069, 10512, 10513, 11284, 11630, 13377, 15997, 19317),
	},
	{
		containers = {22243, 22244, 21340, 21341, 21342},
		items = Set(6265),
	},
	{
		containers = {22246, 22248, 22249},
		items = Union(
			ENCHANTING_MATERIALS,
			Set(6218, 6339, 11130, 11145, 16207)
		),
	},
	{
		containers = {22250, 22251, 22252},
		items = Union(HERBS, SEEDS)
	},
}

-- TODO: Tiers

------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------

_G.SLASH_MORONSORT1 = "/ms"
_G.SLASH_MORONSORT2 = "/msort"
_G.SlashCmdList["MORONSORT"] = _G.SortBags

_G.SLASH_MORONBANKSORT1 = "/mbs"
_G.SLASH_MORONBANKSORT2 = "/mbsort"
_G.SlashCmdList["MORONBANKSORT"] = _G.SortBankBags