# Craft Profit: CurseForge upload sheet

What to type into each CurseForge field, ready to copy and paste. The steps for a first upload and for releasing an update are in [UPLOADING.md](../UPLOADING.md).

Update this sheet with every release: the zip, the display name and the changelog, and rewrite the description so it covers everything in the new version. The release script won't publish until the zip, display name and changelog name the new version.

## A. Project form

**Project name**
```
Craft Profit
```

**Summary**
```
A lightweight panel that shows profit or loss on every craft and crafting order at a glance, ranks patron orders by profit, and adds what-if qualities, proc tracking and a shopping list for missing materials. Prices from TSM or Auctionator.
```

**Main category:** `Professions`
**Additional categories:** `Auction & Economy`

**License:** `MIT License`

**Logo / avatar:** `CraftProfit\images\logo-400.png`

**Description** (paste everything between the lines)

---
```markdown
## Is this craft worth it?

Craft Profit is a **lightweight** addon: one small panel next to your profession window that answers one question in gold, **profit or loss?**

No simulations to set up and nothing to configure. Open your profession, pick a recipe or a crafting order, and the answer is there.

### Light by design
- **Small:** a download of about 40 KB.
- **Quiet until you craft.** Apart from the Craft Rank line on tooltips, nothing runs while you play; it wakes up when you open a profession.
- **Updates only when something changes** (a recipe, a material, your bags).
- **Same qualities as the game.** The quality shown is the one Blizzard's crafting window expects.
- **Never touches your crafts.** What you craft is always what's in Blizzard's crafting window.

### Crafting page
- What the item sells for, at the quality you'll actually get (concentration included)
- Minus the 5% auction house cut
- Minus what your materials are worth
- = **Profit** in green or **Loss** in red

### Crafting orders
- The commission you receive, after the consortium cut
- Minus only the materials **you** supply; what the customer provides isn't counted
- Plus the value of sellable patron rewards (currencies like Moxie are listed too)
- = **Profit** or **Loss**

### Which patron order pays best?
On the **Patron** orders tab, the **Shopping list** button lists every patron order with its **profit or loss** in green or red gold, most profitable first, before you take any of them.

- Hover an order for its commission, the materials you supply, its rewards and exactly what you're missing.
- Click an order to add what you're missing for it to the shopping list; the list stays open so you can add several. Or **Add all** to shop for every order at once.
- What the patrons provide is never added, and what you own counts once across all the orders.

### What if I used another quality?
Click a material in the panel to try its next quality. The cost, the quality the item would come out at, and the profit update right away. Nothing in your bags or in Blizzard's crafting window changes.

- On the **crafting page**: is the better quality worth the extra materials?
- On **crafting orders**: does a cheaper quality still meet the order's minimum? The panel warns you in red when it doesn't.

Right-click a material, or click the blue note, to go back to what's in the form.

### Shopping list, for one craft or twenty
Short of something? The **Shopping list** row under your materials turns orange and shows how many items you're missing. Hover it to see exactly what.

- **Click:** a menu adds what you're missing for **1, 5 or 10 crafts**, or any number you type, to an **Auctionator** shopping list called "Craft Profit", with the right amounts and qualities. Each line shows how many items it would add. Add from more recipes and the amounts add up, so one trip to the auction house covers everything.
- **Shift-click:** tracks the recipe in Blizzard's objective tracker instead.
- **Ctrl-click:** clears the shopping list.

Vendor-sold and soulbound materials go to chat instead, since you can't buy them on the auction house. Want a specific quality? Click the material to pick it first, and that's the one added. No Auctionator? A click tracks the recipe.

### Can I craft it at max rank?
Hover any item you can craft, in your bags, at the auction house or in a chat link, and its tooltip shows your **Craft Rank**: the highest rank this character can make it at with top-quality materials.

- **Max rank** in green, or **Rank 3 of 5** in orange when you can't reach the top yet.
- If concentration gets you a higher rank, you see that rank and the concentration it takes: `Max rank (38 concentration)`.
- It updates each time you open your profession window, so after you gain skill or spend specialization points, open it once.

### Procs, celebrated
When a craft procs **multicraft** or **resourcefulness**, the bonus gold pops up over your profit with a coin sound and a gold flash. A **Procs** section lists the extra items and the materials you got back, and Profit/Loss shows what that craft **really** made.

### Session total
Right under Profit/Loss: `This session (12 crafts)  +8,431g`. Every craft's real result since you logged in, procs included. Click it to reset it.

### Prices
Uses **TradeSkillMaster** or **Auctionator** (you need one of them). Vendor-sold materials like vials and thread use the vendor price. Anything without a price is flagged, so you know when a number is incomplete.

### Options
Click the gear on the panel or type **/craftprofit**:
- Show on the crafting page and/or on crafting orders
- Panel size (60% to 150%), lock or reset its position; drag it anywhere
- Show amounts down to gold, silver or copper
- Proc animation and sound on or off
- Session total on or off, with a reset button
- Shopping list button: click for Auctionator and Shift-click for Blizzard (default), Auctionator only, Blizzard only, or hidden; plus a button to clear the shopping list
- Craft Rank on tooltips on or off, with or without the concentration it takes
- Price addon (Automatic, TSM only or Auctionator only), TSM price types for materials and for crafted items, vendor prices, auction house cut

### Good to know
- Materials you don't have yet are marked **missing**, and their cheapest quality is priced. Every quality you own (bags, bank, warband bank) counts toward what you have.
- For recipes that make a varying amount, the average is used.
- Crafts without a sale price (enchants, recrafts) show material cost only and aren't counted in the session total.
- Patron order profits price the materials you supply at their cheapest quality. An order with a minimum quality may need better materials, so check it before you buy.
- Craft Rank counts only required materials, not optional or finishing ones, and only the professions of the character you're on. Until you've opened your profession window on a character, its tooltips don't show it.
```
---

**Source / Issues links:** leave empty unless you put the code on GitHub.

## B. Upload File form

**File:** `dist\CraftProfit-1.7.0.zip`

**Display name**
```
Craft Profit 1.7.0
```

**Release type:** `Release`

**Game versions:** Retail `12.1.0` and `12.1.5`.

**Changelog** (paste only the newest part; paste older parts too if they never went up)
```markdown
1.7.0
- Craft Rank on tooltips: hover an item you can craft, in your bags, at the auction house or in a chat link, to see the highest rank this character can make it at with top-quality materials. Max rank shows in green, a lower rank (like Rank 3 of 5) in orange.
- When concentration reaches a higher rank, that rank is shown with the concentration it takes, e.g. "Max rank (38 concentration)".
- New Tooltips options: turn the Craft Rank line off, or just the concentration.
- It updates each time you open your profession window, so open it once on each character to start, and again after you gain skill or spend specialization points.

1.6.0
- Patron orders, ranked: the Shopping list button on the Patron orders tab now opens a list of every patron order with its profit or loss in green or red gold, most profitable first, and how many materials you're missing for each.
- Hover an order to see its commission, the materials you supply, its rewards (sellable ones with their value, currencies like Moxie listed too) and exactly what's missing.
- Click an order to add what you're missing for it to the shopping list. The list stays open, so you can add several. Add all is still at the bottom, and orders you don't know the recipe for are listed greyed out.

1.5.0
- Every patron order at once: a Shopping list button on the Patron orders tab adds what you're missing for all the orders in the list to Auctionator's "Craft Profit" shopping list. What the patrons provide isn't added, and materials you own count once across all the orders. Orders whose recipe you don't know are skipped. Ctrl-click the button to clear the list.
- It adds the cheapest quality of each material, so check orders with a minimum quality before you buy.

1.4.1
- Reset the session total right from the panel: click the "This session" row, then confirm. (The Reset button in the options still works too.)

1.4.0
- Buy for several crafts: clicking the button (now called "Shopping list") opens a menu to add what's missing for 1, 5 or 10 crafts, or any number you type. Each line shows how many items it would add. The last number you typed stays in the menu until you log out.
- The menu can also track the recipe and clear the shopping list. Shift-click and Ctrl-click still do that directly.
- With Auctionator, the Shopping list row now always shows (grey when nothing's missing for one craft), since you may still be short for more crafts.

1.3.1
- Missing materials button: by default, a click adds to the Auctionator shopping list and a Shift-click tracks the recipe in Blizzard's objective tracker. Without Auctionator, a click tracks the recipe.
- Ctrl-click the missing materials button to clear the "Craft Profit" shopping list. There's also a Clear button in the options.
- A divider line between the materials and their total cost.
- Shorter panel: the commission and the consortium cut are now one line, "Commission (after 10% cut)", and the sale price and the AH cut are one line, "Sells for (after 5% AH cut)".
- Shorter missing materials tooltip.
- Fixed: a panel tooltip didn't update after clicking until you moved the mouse away and back.

1.3.0
- Missing materials button: when you're short of materials, click the orange button under Materials cost to add just what's missing to an Auctionator shopping list ("Craft Profit"), or to track the recipe in Blizzard's objective tracker.
  - New option to choose which.
  - Auctionator: adds the exact amount and quality you're short. Clicking again adds to the list. Vendor-sold and soulbound materials are listed in chat instead.
  - Pick a quality by clicking a material first, and that's the quality added.

1.2.1
- Behind-the-scenes cleanup, no visible changes. Future Blizzard patches will be quicker to support.

1.2.0
- What-if qualities: click a material in the panel to try its next quality. Right-click a material, or click the note at the bottom, to go back to what's in the form.
  - Crafting page: the material cost, the expected item quality and the sale price update.
  - Crafting orders: works on the materials you supply. The panel shows the quality you'd get and warns when it's below the order's minimum.
- Only the panel changes; your real craft still uses what's in the form.

1.1.2
- Patron order rewards now also list currencies like Artisan's Moxie (shown, but not counted as gold).
- Bigger, easier to read text on the panel.

1.1.1
- Fixed: on a crafting order that was already crafted (waiting to be fulfilled), materials the customer provided were counted as yours, showing a loss that wasn't real.

1.1.0
- Multicraft and resourcefulness procs: the bonus gold pops up over the Profit line with a coin sound, and the panel flashes gold.
- After a proc, a "Procs" section lists the extra items and returned materials with their value, and Profit/Loss shows what that craft really made.
- Session total: what all your crafts made since you logged in, under Profit/Loss. Can be hidden or reset in the options.
- Options to turn the proc animation and sound off.

1.0.0 - First release.
- Profit panel on the crafting page: sale price at your expected quality, minus the AH cut, minus materials.
- Profit panel on crafting orders: commission after the consortium cut, minus the materials you supply, plus sellable patron rewards.
- Prices from TradeSkillMaster or Auctionator, with vendor prices for vendor items.
- Options (/craftprofit): show per page, lock, size, reset position, gold/silver/copper rounding, price addon, TSM price types, vendor prices, AH cut.
```

**Related projects:** add both as **Optional Dependency**:
- `TradeSkillMaster`
- `Auctionator`
