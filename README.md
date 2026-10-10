# Craft Profit

A lightweight addon: one small panel next to your profession window that tells you, in gold, whether a craft or a crafting order makes or loses money.

- **Crafting page:** what the item sells for, minus the 5% auction house cut, minus your materials.
- **Crafting orders:** the commission you receive (after the consortium cut), minus the materials **you** supply, plus any sellable patron rewards.

- **Procs:** when a craft procs multicraft or resourcefulness, the bonus gold pops up over the Profit line with a coin sound, a **Procs** section lists the extra items and returned materials with their value, and Profit/Loss changes to what that craft really made. It goes back to the normal forecast on your next craft without a proc, or when you pick another recipe.

- **Shopping list:** adds what you're short of, for one or more crafts or for every patron order at once, to an Auctionator shopping list, or as a TSM search to copy.

- **Session total:** under Profit/Loss, what all your crafts made since you logged in on this character (a `/reload` keeps it). Crafts without a price, like enchants, aren't counted. Click it to reset it to zero.

- **Best rank on tooltips:** an item you can craft shows the highest rank you can make it at with top-quality materials, anywhere you see its tooltip.

It stays light: nothing runs until you open your profession window. It doesn't simulate procs in advance; it shows you the gold when they happen.

Requires **TradeSkillMaster** or **Auctionator** for prices. Built for WoW Midnight 12.1.

## Install
Copy the `CraftProfit` folder to `World of Warcraft\_retail_\Interface\AddOns\` and restart the game.

## Use
Open your profession and pick a recipe, or open a crafting order. The panel appears to the right of the window.

- Materials are priced at the quality you actually put in the form. If a slot is empty (you don't own the material), it's marked **missing** and the cheapest quality is assumed.
- The sale price follows the quality you'll get, including concentration if you turn it on.
- Vendor-sold materials (vials, thread...) use the vendor price.
- For recipes that make a varying amount, the average is used.
- Materials without any price are shown in red. Profit is then too high, so take it with a grain of salt.
- Drag the panel to move it. It remembers where you put it.

### What if I used another quality?
**Click a material** that comes in several qualities (it has a quality icon) to try its next quality. Changed materials are marked **simulated**.

- **Crafting page:** the panel updates the material cost, the quality the item would come out at, and the sale price.
- **Crafting orders:** works on the materials you supply. The panel shows the quality you'd get and warns in red when it's below the order's minimum quality, so you can see whether a cheaper quality still does the job.

- **Right-click** a material to put it back, or click the blue note at the bottom to reset all of them.
- Only the panel changes. Your real craft still uses what's in Blizzard's form, and procs and the session total always count the real craft.
- Picked qualities reset when you choose another recipe.
- If the game can't predict the quality for a mix (for example with materials you don't own), the panel says so and keeps the form's quality for the sale price.

**Cheaper rank to buy:** on a crafting order, when the form uses a rank you own and buying another rank comes out cheaper, a blue line under that material says how much it saves, e.g. **[rank 1] saves 2g 40s**. What you own counts at what it would sell for after the 5% auction house cut, so the line only shows when buying really comes out ahead, and only for a rank that still meets the order's minimum quality. Click it to use that rank: the panel and the shopping list switch to it. Hover it for the numbers.

### Shopping list
Under **Materials cost** there's a **Shopping list** row. It turns orange and shows a count when you're short of materials for one craft; hover it to see what's missing.

**Click** it to open a menu:

- **For 1 / 5 / 10 crafts:** adds what you're missing for that many crafts, with the amount and quality, to Auctionator's **Craft Profit** shopping list. Each line shows how many items it would add. Open the list in Auctionator's Shopping tab at the auction house.
- **Other amount...:** type any number of crafts. The last number you typed stays in the menu until you log out or `/reload`.
- **Clear shopping list.**

Adding again (or on another recipe) adds to the amounts already on the list. Vendor-sold and soulbound materials are listed in chat instead. Every quality you own counts toward a material, and the cheapest quality is the one added. To buy a specific quality, click the material to pick it first (see above).

Shortcut: **Ctrl-click** clears the list, without the menu.

**Just one material:** **Shift-click** a material in the panel to add only what you're missing of it, for one craft. Pick a quality first by clicking it, and that quality is what gets added. With TSM, you get a search for just that material.

**Separate lists:** each character and profession gets its own list, like **Craft Profit - Thrall - Blacksmithing**. Turn off **one shopping list per character** or **per profession** in the options to share lists instead.

**TSM without Auctionator:** the row says **Copy TSM search** instead, with the same menu. Pick an amount and a box shows a search, already selected: press Ctrl+C and paste it into the search box on TSM's Shopping tab. It searches for exactly the ranks you're missing and stops at the amounts you need. With neither Auctionator nor TSM, the row is hidden.

**Both installed?** Pick **Shop with: Auctionator shopping list** (default) or **TSM search to copy** at the bottom of the menu, at the bottom of the Patron orders list, or in the options.

**Patron orders:** on the **Patron** orders tab, a **Shopping list** button sits at the right of the tabs. Click it for a list of every patron order with its profit or loss, in green or red, most profitable first, and how many materials you're missing for it. Like Blizzard's order list, an order that needs more than rank 1 shows its minimum quality icon after its name. A green check marks the orders you already have everything for, in the qualities that make the most profit. Hover an order to see its commission, rewards and material cost, and exactly what's missing. **Click an order** to add what you're missing for it to the shopping list, or **Shift-click** it to take that back off. Shift-click removes what the order added since you logged in, including through Add profitable or Add all, or what it's missing now if it added nothing. Orders whose recipe you don't know are listed greyed out. Ctrl-click the button clears the list. The button needs Auctionator or TSM: with only TSM, clicking an order (or **Copy profitable**, **Copy all**) gives you a TSM search to copy instead.

At the bottom of the list:
- **Add profitable** adds what you're missing for every order that makes a profit and whose minimum quality you can reach.
- **Add all** adds what you're missing for every order at once, except the ones whose minimum quality you can't reach even with the best materials and concentration.

Either way, materials you own count once across all the orders, and what the patrons provide is never added.

**Minimum quality:** for an order with a minimum quality, profit and the shopping list use the cheapest mix of material qualities that still reaches it, counting what the patron provides. Hover the order to see the minimum and the qualities picked. If only concentration gets you there, the order shows how much it takes, e.g. **(38 concentration)**. If even the best materials can't reach it, it says **can't craft**, moves to the bottom of the list without a profit, and Add profitable and Add all skip it. Orders without a minimum use the cheapest quality of each material. Either way, what you own counts at what it would sell for after the 5% auction house cut, so a rank you have is only swapped for one to buy when that comes out cheaper.

**Concentration:** the orders that need concentration share what you have, and the top of the list shows how much they use. By default the orders that make the most gold per concentration point get it first; the options, or the choice at the bottom of the list, can put orders that reward profession knowledge first instead. Once it runs out, the rest say **not enough concentration** in red, their profit turns grey, and Add profitable and Add all skip them. Order tooltips also show how much knowledge a reward gives.

You can hide the Shopping list row and the Patron orders button in the options. The options also have a **Clear** button for the list.

### Best rank on tooltips
Hover an item you can craft, in your bags, at the auction house or in a chat link, and its tooltip gets a **Craft Rank** line: the highest rank each of your characters can make it at with the top quality of every material.

- One line for each character that knows the recipe, in its class color, best rank first. Characters on another realm show their realm too. Switch to **this character only** in the options for a single line.
- Deleted, renamed or moved a character? Forget it in the options (**Saved characters: Forget...**).

- **Max rank** in green when you can make it at the top rank, or **Rank 3 of 5** in orange when you can't yet.
- If concentration reaches a higher rank, that rank is shown, with the concentration it takes, e.g. **Max rank (38 concentration)**. You can hide the concentration in the options.
- Optional and finishing materials aren't counted.
- Only for recipes that come in ranks.
- It updates each time you open your profession window, so after you gain skill or spend specialization points, open the window once on that character. A character shows up after you've opened its profession window once.

## Options
Click the gear on the panel or at the top of the Patron orders list, type `/craftprofit`, or go to **Esc → Options → AddOns → Craft Profit**.

| Option | What it does |
|---|---|
| Show on the crafting page / on crafting orders | Turn the panel on or off for each page. |
| Lock panel position | Stops the panel from being dragged. |
| Panel size | Size of the whole panel, 60% to 150%. |
| Panel position: Reset | Puts the panel back next to the profession window. |
| Show amounts down to | Gold, silver (default) or copper. |
| Patron orders: Spend concentration on | Most profit (default): the most gold per concentration point first. Knowledge first: orders that reward profession knowledge first, then by profit. Also at the bottom of the Patron orders list. |
| Show the Shopping list button | The Shopping list row and the Patron orders button. On by default; hidden anyway without Auctionator or TSM. |
| Shop with | With Auctionator and TSM both installed: Auctionator shopping list (default) or TSM search to copy. Also at the bottom of the Shopping list menus. |
| One shopping list per character / per profession | On by default. Either or both split the Craft Profit list, e.g. Craft Profit - Thrall - Blacksmithing. |
| Auctionator shopping list: Clear | Empties the shopping list. With one list per profession and no profession window open, it empties all this character's profession lists. |
| Animate multicraft & resourcefulness procs | On by default. |
| Coin sound on procs | On by default. |
| Show this session's total | On by default. |
| Session total: Reset | Starts the session total from zero. |
| Show the best rank you can craft | The **Craft Rank** line on item tooltips. On by default. |
| Show it for | All your characters (default) or this character only. |
| Saved characters: Forget... | Pick a character you deleted, renamed or moved to take it off Craft Rank tooltips. |
| Show the concentration it takes | Adds the concentration when the best rank needs it. On by default. |
| Price addon | Automatic (TSM, then Auctionator for anything TSM has no price for), TSM only, or Auctionator only. |
| TSM price for materials / crafted items | Market value (default), lowest auction right now, historical price or region market average. |
| Use vendor price for vendor items | On by default. |
| Subtract auction house cut (5%) | On by default. |

## Notes
- With Auctionator, prices come from your own auction house scans. With TSM, the TSM desktop app keeps them up to date for you. With Auctionator, the bottom of the panel says how old its oldest price is (**seen today**, or **oldest 4 days ago** in red once it's 3 days or more), and each material's tooltip says when Auctionator last saw it. Visit the auction house to refresh them.
- A big Blizzard update to the profession window may need a Craft Profit update too.
