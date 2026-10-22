# Changelog

## 1.21.1
- Fixed: when an order crafted from the Patron tab procced resourcefulness, the bonus gold and the gold border flash didn't show.

## 1.21.0
- Patron orders right in Blizzard's Patron tab: instead of a separate list behind a Shopping list button, Blizzard's own order list now shows Craft Profit's columns where Patron Name, Commission and Reagents were. **Materials** says **Ready** or how many you're missing, **Rewards** shows profession knowledge, Artisan's Moxie and items as icons, and **Profit** shows the order's profit or loss in green or red, with the concentration it takes. Hover any of them for the details.
- Each order has its own buttons at the end of its row: a cart adds what you're missing for it to the shopping list (Shift-click takes it back off), and the craft button starts, crafts and completes it, one click per step.
- Click the **Profit** header to sort the orders by profit, most first; click it again for least first.
- **Add profitable** and **Add all** sit above the list, next to the order tabs. Under the list: the concentration the orders use, this session's total, and a gear with the list's choices (which orders get concentration first, Optimize concentration, Shop with, Clear shopping list, options).
- With only TSM, the Patron tab builds one TSM search as you click carts, Copy profitable or Copy all, with every order's materials added up. Click **TSM search** under the list to copy it again; it follows what you're still missing.
- A resourcefulness proc on an order crafted from the tab pops up from that order's profit.
- Orders you complete leave the list right away.
- New option, **Show Craft Profit on the Patron tab**: turn it off to get Blizzard's own columns back.
- After an update, a What's New window shows what changed since the version you had.

## 1.20.1
- Fixed: crafts with nothing to sell (no auction price, like treatises, or an enchant or a recraft) didn't count what their materials cost. The panel now shows them as a Loss of that cost, and they count that way in the session total, less what resourcefulness gives back.

## 1.20.0
- The session total now also shows at the bottom of the Patron orders list, so you can follow it while you craft from the list. Click it to reset it, as on the panel.

## 1.19.0
- The most profitable materials on the crafting page: **Use Most Profitable Reagents** and **Optimize Concentration** now also sit above Blizzard's Use Best Quality Reagents on the crafting page, and the panel's "Use the most profitable materials" row shows there too. They pick the rank that makes the most gold after what its materials cost, and the cheapest materials that make it. Concentration stays as you set it: with it on, Optimize Concentration picks the qualities that reach the rank with the least of it. Items with no sale price get the cheapest materials that keep the rank they come out at now.
- Shopping lists no longer have "Craft Profit" in their names: they're named after the character and profession, like "Thrall - Blacksmithing" (or "Crafting" with both of those options off). Your old lists move to the new names at your next login, along with what's on them.

## 1.18.2
- Fixed: the Patron orders list stayed tall, with empty space at the bottom, after an order left it. It now fits its orders, and scrolls only when they don't fit.

## 1.18.1
- Fixed: when a proc's bonus gold popped up and floated away, the gold, silver and copper coin icons stayed behind. They now move with the amount.

## 1.18.0
- Resourcefulness on the Patron orders list: when an order you craft from the list procs, the bonus gold pops up over the list and its border flashes gold, like on the panel. The same options turn the animation and the coin sound off.

## 1.17.0
- The shopping list checks itself off: materials Craft Profit added to your Auctionator shopping list come off as you get them, whether bought, looted, taken from the mailbox or crafted. Chat says what came off, and when the list is done. Moving things between your bags, bank and warband bank doesn't count, and lines you add yourself in Auctionator stay. Turn it off with "Check off what you get" in the options.
- Fixed: on a crafting order with a minimum quality, the Shopping list could add a rank that doesn't reach it (usually the cheapest). It now adds the ranks that do, the same ones the Patron orders list picks.
- Fixed: optional and finishing reagents that raise your skill no longer count toward an order's minimum quality in Craft Profit's suggestions. With one in the form, a cheaper rank could be suggested that only reached the minimum thanks to it.
- Optimize Concentration on the crafting order form fades while Use Most Profitable Reagents is off, since it doesn't change the form then. It still sets the Patron orders list's picks.

## 1.16.1
- Fixed: the game could stutter for a few seconds after you opened your profession window, while Craft Rank updated. It now updates in the background without slowing the game down.

## 1.16.0
- Craft Rank: a new "with optional reagents" line under a character's rank, when optional reagents make the item harder to craft, like the ones that raise its item level. It shows the best rank with the hardest one in each optional slot, at its top rank, and the concentration it takes. Open your profession window once to update it.

## 1.15.0
- Optimize concentration: a new checkbox in the Patron orders list, on the crafting order form and in the options. Orders that need concentration to reach their minimum quality use the material qualities that need the least of it, and the cheapest of those, so your concentration covers more orders. The materials cost more.
- The crafting order form stacks its checkboxes: Optimize Concentration, Use Most Profitable Reagents, then Blizzard's Use Best Quality Reagents.
- Shopping list: a click adds what you're missing for one craft right away. Shift-click opens the menu for 1, 5, 10 or any number of crafts.
- Simulated quality says how much concentration it uses, like "(38 concentration)", when concentration is on.
- The Patron orders list updates right away when you switch "Spend concentration on". "Knowledge first, then profit" is now just "Knowledge first".

## 1.14.0
- Craft patron orders right from the list: an order you have everything for gets a small button at the end of its row. Each click does the next step, and its icon shows which: a scroll to start the order, a hammer to craft it with the qualities the list picked (and concentration if its minimum quality needs it), a watch while it crafts, then coins to complete it and collect the rewards. Chat confirms each step.
- Only one order can be started at a time, so while one is in progress only that order shows the button. It stays in the list until it's complete.
- Orders crafted from the list count toward the session total, resourcefulness included.
- The Patron orders list now opens under its button and stays put while you work through it, with taller rows and bigger icons.
- An order's tooltip shows its profit or loss at the bottom, under the rewards and what's missing, with the click hints after it.

## 1.13.0
- Use Most Profitable Reagents: a new checkbox on the crafting order form, next to Blizzard's Use Best Quality Reagents. While it's on, every order you open gets the most profitable materials put in by itself: the cheapest qualities that still reach the order's minimum quality, the same ones the Patron orders list prices it with. Concentration is turned on when the minimum quality needs it.
- A slot you change afterwards stays as you set it. Unticking the checkbox puts back Blizzard's own pick. Only one of the two checkboxes can be on at a time.
- Without the checkbox, a blue "Use the most profitable materials" row under the materials puts them in once, and says how much more gold they make. With it on, the row shows when a material couldn't go in because you're short of it.

## 1.12.0
- Shift-click a material in the panel to add just what you're missing of it, for one craft, to the shopping list (or a TSM search). Pick a quality first by clicking it, and that quality is added.
- Works on every material you're short of, including ones without qualities. Its tooltip shows how many are missing.

## 1.11.0
- TSM shopping: without Auctionator, the Shopping list row becomes "Copy TSM search", with the same menu for 1, 5, 10 or any number of crafts. It gives you a search to paste into TSM's Shopping tab, for exactly the ranks and amounts you're missing.
- The Patron orders list now works with TSM too: click an order, or Copy profitable / Copy all, for a search to paste.
- Both installed? Pick "Shop with": Auctionator shopping list or TSM search, at the bottom of the Shopping list menus or in the options.
- Price age: with Auctionator prices, the bottom of the panel says how old the oldest price is ("seen today", or "oldest 4 days ago" in red from 3 days on), and each material's tooltip says when Auctionator last saw it.
- Removed: tracking the recipe in Blizzard's objective tracker (Shift-click and the menu entry). Blizzard's own Track Recipe checkbox in the profession window does the same. The Shopping list button option is now just on or off.
- Without Auctionator or TSM, the Shopping list row is hidden.

## 1.10.0
- Separate shopping lists: each character and profession now gets its own Auctionator list, like "Craft Profit - Thrall - Blacksmithing". Turn either off in the options to share lists as before.
- What's already on the old "Craft Profit" list stays there; new materials go to the new lists.
- Clear in the options, with no profession window open, empties the lists of all this character's professions.
- Forget a character: Saved characters: Forget... in the Tooltips options takes a deleted, renamed or moved character off Craft Rank tooltips.

## 1.9.0
- Craft Rank for all your characters: the tooltip lists every character that knows the recipe, in its class color, best rank first. Characters on another realm show their realm too.
- New Tooltips option, Show it for: all your characters (default) or this character only.
- A character shows up once you log in on it, if it already had Craft Rank from 1.7 or 1.8. Otherwise open its profession window once.

## 1.8.0
- Patron orders, optimized: each order in the Patron list now uses the cheapest mix of material ranks that still meets its minimum quality, counting what the patron provides. Its profit, missing count and shopping list all follow those ranks. Hover an order to see its minimum quality and the ranks picked.
- What you already own counts at what it would sell for after the 5% auction house cut, so a rank you have is only swapped for one to buy when that really comes out cheaper.
- Orders you can't reach even with the best materials and concentration say "can't craft", move to the bottom of the list and are never added to the shopping list.
- Concentration: orders that need it share what you have, most gold per concentration point first, or orders that reward knowledge (Flicker, Glimmer) first. The rest say "not enough concentration". Pick which at the bottom of the list, or in the new Patron orders section of the options.
- Add profitable: adds what you're missing for every order that makes a profit and that you can craft. Add all now skips orders you can't craft.
- A green check marks the orders you already have everything for, in the most profitable ranks.
- Each order shows its minimum quality icon after its name, like Blizzard's order list.
- Shift-click an order to take its materials back off the shopping list.
- Add, Clear and the concentration choice keep the list open, and a gear next to its title opens the options.
- On an open crafting order: when buying a different rank beats using the one you own, a blue line under that material says how much it saves. Click it to switch, and the shopping list buys it.

## 1.7.0
- Craft Rank on tooltips: hover an item you can craft, in your bags, at the auction house or in a chat link, to see the highest rank this character can make it at with top-quality materials. Max rank shows in green, a lower rank (like Rank 3 of 5) in orange.
- When concentration reaches a higher rank, that rank is shown with the concentration it takes, e.g. "Max rank (38 concentration)".
- New Tooltips options: turn the Craft Rank line off, or just the concentration.
- It updates each time you open your profession window, so open it once on each character to start, and again after you gain skill or spend specialization points.

## 1.6.0
- Patron orders, ranked: the Shopping list button on the Patron orders tab now opens a list of every patron order with its profit or loss in green or red gold, most profitable first, and how many materials you're missing for each.
- Hover an order to see its commission, the materials you supply, its rewards (sellable ones with their value, currencies like Moxie listed too) and exactly what's missing.
- Click an order to add what you're missing for it to the shopping list. The list stays open, so you can add several. Add all is still at the bottom, and orders you don't know the recipe for are listed greyed out.

## 1.5.0
- Every patron order at once: a Shopping list button on the Patron orders tab adds what you're missing for all the orders in the list to Auctionator's "Craft Profit" shopping list. What the patrons provide isn't added, and materials you own count once across all the orders. Orders whose recipe you don't know are skipped. Ctrl-click the button to clear the list.
- It adds the cheapest quality of each material, so check orders with a minimum quality before you buy.

## 1.4.1
- Reset the session total right from the panel: click the "This session" row, then confirm. (The Reset button in the options still works too.)

## 1.4.0
- Buy for several crafts: clicking the button (now called "Shopping list") opens a menu to add what's missing for 1, 5 or 10 crafts, or any number you type. Each line shows how many items it would add. The last number you typed stays in the menu until you log out.
- The menu can also track the recipe and clear the shopping list. Shift-click and Ctrl-click still do that directly.
- With Auctionator, the Shopping list row now always shows (grey when nothing's missing for one craft), since you may still be short for more crafts.

## 1.3.1
- Missing materials button: by default, a click now adds to the Auctionator shopping list and a Shift-click tracks the recipe in Blizzard's objective tracker. Without Auctionator, a click tracks the recipe. The Auctionator-only and Blizzard-only options are still there.
- Ctrl-click the missing materials button to clear the "Craft Profit" shopping list. There's also a Clear button in the options.
- A divider line between the materials and their total cost.
- Shorter panel: the commission and the consortium cut are now one line, "Commission (after 10% cut)", and the sale price and the AH cut are one line, "Sells for (after 5% AH cut)".
- Shorter missing materials tooltip: just the materials and what a click does.
- Fixed: a panel tooltip didn't update after clicking until you moved the mouse away and back (for example "track" / "stop tracking").

## 1.3.0
- Missing materials button: when you're short of materials, click the orange button under Materials cost to add just what's missing to an Auctionator shopping list ("Craft Profit"), or to track the recipe in Blizzard's objective tracker.
  - New option to choose which: Automatic (Auctionator when installed), Auctionator, Blizzard, or hide the button.
  - Auctionator: adds the exact amount and quality you're short. Clicking again adds to the list. Vendor-sold and soulbound materials are listed in chat instead.
  - Pick a quality by clicking a material first, and that's the quality added.

## 1.2.1
- Behind-the-scenes cleanup, no visible changes. Future Blizzard patches will be quicker to support.

## 1.2.0
- What-if qualities: click a material in the panel to try its next quality. Right-click a material, or click the note at the bottom, to go back to what's in the form.
  - Crafting page: the material cost, the expected item quality and the sale price update.
  - Crafting orders: works on the materials you supply. The panel shows the quality you'd get and warns when it's below the order's minimum.
- Only the panel changes; your real craft still uses what's in the form.

## 1.1.2
- Patron order rewards now also list currencies like Artisan's Moxie (shown, but not counted as gold).
- Bigger, easier to read text on the panel.

## 1.1.1
- Fixed: on a crafting order that was already crafted (waiting to be fulfilled), materials the customer provided were counted as yours, showing a loss that wasn't real.

## 1.1.0
- Multicraft and resourcefulness procs: the bonus gold pops up over the Profit line with a coin sound, and the panel flashes gold.
- After a proc, a "Procs" section lists the extra items and returned materials with their value, and Profit/Loss shows what that craft really made.
- Options to turn the proc animation and sound off.
- Session total: what all your crafts made since you logged in, under Profit/Loss. Can be hidden or reset in the options.

## 1.0.0
- First release.
- Profit panel on the crafting page: sale price at your expected quality, minus the AH cut, minus materials.
- Profit panel on crafting orders: commission after the consortium cut, minus the materials you supply, plus sellable patron rewards.
- Prices from TradeSkillMaster or Auctionator, with vendor prices for vendor items.
- Options panel (`/craftprofit`): show per page, lock, size, reset position, gold/silver/copper rounding, price addon, TSM price types, vendor prices, AH cut.
