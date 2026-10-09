# Changelog

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
