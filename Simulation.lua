-- Craft Profit: "what if" qualities. Clicking a material in the panel picks
-- another quality for it. Only the panel changes; Blizzard's form and the real
-- craft are untouched.
local _, ns = ...

local Simulation = {}
ns.Simulation = Simulation

-- slotIndex -> itemID of the picked quality, for one recipe or order.
Simulation.picks = {}
local picksFor

-- Picks belong to one recipe or order; switching to another starts clean.
-- Returns whether anything is being simulated.
function Simulation.UseFor(key)
	if picksFor ~= key then
		wipe(Simulation.picks)
		picksFor = key
	end
	return next(Simulation.picks) ~= nil
end

-- Whether a material in the panel can be switched to another quality.
function Simulation.CanChange(material)
	return material.slot ~= nil and ns.Blizzard.IsQualitySlot(material.slot)
end

-- Left-click: the next quality. Right-click: back to what's in the form.
function Simulation.Cycle(material, mouseButton)
	local picks = Simulation.picks
	if mouseButton == "RightButton" then
		picks[material.slotIndex] = nil
	else
		local options = material.slot.reagents
		local nextID = options[1].itemID
		for i, reagent in ipairs(options) do
			if reagent.itemID == material.itemID then
				nextID = options[i % #options + 1].itemID
				break
			end
		end
		-- Back on what the form really has: that's not a simulation any more.
		picks[material.slotIndex] = nextID ~= material.formItemID and nextID or nil
	end
	ns.Panel.Refresh()
end

function Simulation.Reset()
	wipe(Simulation.picks)
	ns.Panel.Refresh()
end
