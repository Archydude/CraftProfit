# Craft Profit

A lightweight addon: one small panel next to your profession window that tells you, in gold, whether a craft or a crafting order makes or loses money.

- **Crafting page:** what the item sells for, minus the 5% auction house cut, minus your materials. With nothing to sell (no auction price, an enchant, a recraft), it's a loss of what the materials cost.
- **Crafting orders:** the commission you receive (after the consortium cut), minus the materials **you** supply, plus any sellable patron rewards.

- **Procs:** when a craft procs multicraft or resourcefulness, the bonus gold pops up over the Profit line with a coin sound, a **Procs** section lists the extra items and returned materials with their value, and Profit/Loss changes to what that craft really made. It goes back to the normal forecast on your next craft without a proc, or when you pick another recipe.

- **The most profitable materials:** one click, or a checkbox on the crafting page and the order form, puts in the material qualities that make the most gold.

- **Shopping list:** adds what you're short of, for one or more crafts or for every patron order at once, to an Auctionator shopping list, or as a TSM search to copy. The Auctionator list checks materials off as you get them.

- **Session total:** under Profit/Loss, what all your crafts made since you logged in on this character (a `/reload` keeps it), including orders crafted from the Patron tab, where it also shows under the order list. Crafts whose item has no sale price, like enchants and treatises, count as a loss of what their materials cost, less what resourcefulness gives back. Click it to reset it to zero.

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

**Cheaper rank to buy:** on a crafting order, when the form uses a rank you own and buying another rank comes out cheaper, a blue line under that material says how much it saves, e.g. **[rank 1] saves 2g 40s**. What you own counts at what it would sell for after the 5% auction house cut, so the line only shows when buying really comes out ahead, and only for a rank that still meets the order's minimum quality on its own, without an optional or finishing reagent that raises your skill. Click it to use that rank: the panel and the shopping list switch to it. Hover it for the numbers.

**Use the most profitable materials:** when the form holds materials that make less gold than they could, a blue row under the materials says how much more the best ones make. Click it to put them in Blizzard's form. What you own counts at what it would sell for. A material you don't have enough of stays as it was, and chat says what to buy. Hover the row to see what it puts in.

- **On a crafting order:** the cheapest qualities that still reach the order's minimum quality, the same materials the Patron tab prices each order with. If reaching the minimum quality takes concentration, it turns that on too.
- **On the crafting page:** the rank that makes the most gold after what its materials cost, and the cheapest materials that make it. Concentration stays as you set it: with it on, the ranks it reaches count. With no sale price for the item, the row offers the cheapest materials that keep the rank it comes out at now.

**Use Most Profitable Reagents:** a checkbox on the crafting order form and the crafting page, above Blizzard's **Use Best Quality Reagents**. While it's on, every order or recipe you open gets the most profitable materials put in by itself. A slot you change afterwards stays as you set it. Unticking it puts back the materials Blizzard picks by itself, and turns concentration back off if the checkbox turned it on. Only one of the two checkboxes can be on: checking one unchecks the other. It's the same setting on both pages. It shows wherever Blizzard's checkbox does, on orders and recipes whose materials come in qualities. Above it, **Optimize Concentration** (see Patron orders below) works the same way: on the crafting page, with concentration on, it picks the qualities that reach the rank with the least concentration.

### Shopping list
Under **Materials cost** there's a **Shopping list** row. It turns orange and shows a count when you're short of materials for one craft; hover it to see what's missing.

**Click** it to add what you're missing for one craft. **Shift-click** it to open a menu:

- **For 1 / 5 / 10 crafts:** adds what you're missing for that many crafts, with the amount and quality, to an Auctionator shopping list (see Separate lists below). Each line shows how many items it would add. Open the list in Auctionator's Shopping tab at the auction house.
- **Other amount...:** type any number of crafts. The last number you typed stays in the menu until you log out or `/reload`.
- **Clear shopping list.**

Adding again (or on another recipe) adds to the amounts already on the list. Vendor-sold and soulbound materials are listed in chat instead. Every quality you own counts toward a material, and the cheapest quality is the one added. On a crafting order whose minimum quality the form doesn't reach, the list adds the qualities that do reach it instead, the same ones the Patron tab picks. To buy a specific quality, click the material to pick it first (see above).

Shortcut: **Ctrl-click** clears the list, without the menu.

**Checked off as you get them:** materials come off the list as they arrive: bought at the auction house, looted, taken from the mailbox or crafted. (Auction house items that aren't commodities come by mail, so they're checked off once you take them out.) Chat says what came off, and when the list is done. Only what Craft Profit added is checked off: lines you add yourself in Auctionator stay. Moving things between your bags, bank and warband bank doesn't count. Turn off **Check off what you get** in the options to keep the list until you clear it.

**Just one material:** **Shift-click** a material in the panel to add only what you're missing of it, for one craft. Pick a quality first by clicking it, and that quality is what gets added. With TSM, you get a search for just that material.

**Separate lists:** each character and profession gets its own list, like **Thrall - Blacksmithing**. Turn off **one shopping list per character** or **per profession** in the options to share lists instead; with both off, the list is called **Crafting**. Lists from before 1.19.0, named **Craft Profit - ...**, are moved to the new names the next time you log in, along with what's on them.

**TSM without Auctionator:** the row says **Copy TSM search** instead, with the same menu. Pick an amount and a box shows a search, already selected: press Ctrl+C and paste it into the search box on TSM's Shopping tab. It searches for exactly the ranks you're missing and stops at the amounts you need. With neither Auctionator nor TSM, the row is hidden.

**Both installed?** Pick **Shop with: Auctionator shopping list** (default) or **TSM search to copy** at the bottom of the menu, in the gear menu at the bottom of the Patron tab, or in the options.

You can hide the Shopping list row and the Patron tab's shopping buttons in the options. The options also have a **Clear** button for the list.

### Patron orders
On the **Patron** orders tab, Blizzard's order list shows Craft Profit's columns where Patron Name, Commission and Reagents were: Materials, Rewards and Profit, then Blizzard's time left, then Actions at the end. Clicking anywhere else on a row still opens the order.

- **Materials:** **Ready** with a green check when you have everything, in the qualities that make the most profit, or how many you're missing, in orange. Hover it to see exactly what's missing. Orders whose recipe you don't know say **Recipe not known** under Profit.
- **Rewards:** what the patron gives besides the commission, as icons: profession knowledge (its count in green), Artisan's Moxie, items. Hover one for its tooltip and what it sells for.
- **Profit:** the order's profit or loss, in green or red: the commission after the cut, plus the rewards that sell, minus the materials you supply. If reaching its minimum quality takes concentration, the amount follows, e.g. **38** with the concentration icon. Hover it for the commission, material cost, rewards and the patron's name, and the qualities picked. Click the **Profit** header to sort the orders by profit, most first; click it again for least first. Clicking Name or the clock sorts the Blizzard way again.
- **Actions:** a cart button when you're missing something: **click** it to add what's missing to the shopping list, or **Shift-click** it to take that back off. Shift-click removes what the order added since you logged in, including through Add profitable or Add all, or what it's missing now if it added nothing. Next to it, the craft button (below). Click the **Actions** header to put the orders you can craft now first (the one you started, then the ones you have everything for); click it again for the ones to shop for first. While it sorts, the header shows the hammer or the cart. Each group goes by profit, and only one header sorts at a time.

**Craft from the list:** a ready order gets a craft button in its Actions. Each click does the next step of that order, and its icon shows which: a scroll to **start** it, a hammer to **craft** it with the qualities picked (and concentration, if its minimum quality needs it), a watch while it's crafting, then coins to **complete** it and collect the rewards. The game asks for a click for each step, and only one order can be started at a time, so while one is in progress only that order has the button, and its Materials say **Started**, **Crafting...** or **Crafted**. Chat confirms each step, and says so if the game turns one down (the recipe needs an anvil nearby, say). When a craft procs resourcefulness, the bonus gold pops up from that order's profit and the list's border flashes gold, as on the panel (the same options turn the animation and the coin sound off).

Above the list, next to the order tabs:
- **Add profitable** adds what you're missing for every order that makes a profit and whose minimum quality you can reach.
- **Add all** adds what you're missing for every order at once, except the ones whose minimum quality you can't reach even with the best materials and concentration.

Either way, materials you own count once across all the orders, and what the patrons provide is never added. With only TSM, they're **Copy profitable** and **Copy all**. Hover them to see how many orders and materials they cover.

**With only TSM:** there's no shopping list, so the Patron tab builds one TSM search instead. Each cart click adds that order to it, and **Copy profitable** and **Copy all** add theirs; every time, a box shows the whole search, already selected: press Ctrl+C and paste it into the search box on TSM's Shopping tab. Amounts add up across the orders, and what you own counts once. **Shift-click** a cart to take its order back out. Carts of the orders in the search are lit. The search follows what you're still missing, so materials you've bought since drop out, and so do orders you complete. Under the list, **TSM search: 3 patron orders** shows the search again when you click it; **Clear TSM search** in the gear menu empties it, and it starts empty each time you log in.

Under the list: how much concentration the orders use, this session's total (click to reset it), and a gear with the list's choices: which orders get your concentration first, Optimize concentration, Shop with, Clear shopping list and the options.

**Minimum quality:** for an order with a minimum quality, profit and the shopping list use the cheapest mix of material qualities that still reaches it, counting what the patron provides. Hover its profit to see the minimum and the qualities picked. If even the best materials can't reach it, its Materials say **Can't craft**, its profit turns grey, and Add profitable and Add all skip it. Orders without a minimum use the cheapest quality of each material. Optional and finishing reagents that raise your skill never count toward reaching the minimum here: they're used up by the craft, so the picks get there without them. Either way, what you own counts at what it would sell for after the 5% auction house cut, so a rank you have is only swapped for one to buy when that comes out cheaper.

**Concentration:** the orders that need concentration share what you have. By default the orders that make the most gold per concentration point get it first; the options, or the gear under the list, can put orders that reward profession knowledge first instead. Once it runs out, the rest show their concentration in red, their profit turns grey, their Materials say **No concentration** when nothing's missing, and Add profitable and Add all skip them.

**Don't use concentration:** the third choice for which orders get concentration. Patron orders then never spend it: an order that only reaches its minimum quality with concentration shows its profit in grey and **No concentration** under Materials, with no cart and no craft button, and Add profitable and Add all skip it. On its order form, Use Most Profitable Reagents and the blue row leave the materials alone. Orders that reach their minimum without concentration work as usual, and the crafting page isn't affected.

**Optimize concentration:** in the gear menu under the list, also on the crafting order form and the crafting page (above Use Most Profitable Reagents) and in the options. With it on, an order that needs concentration uses the material qualities that need the least of it, and the cheapest of those, so your concentration covers more orders. The materials cost more. Use Most Profitable Reagents and the blue row on the order form pick the same materials.

Turn off **Show Craft Profit on the Patron tab** in the options to get Blizzard's own columns back.

### Best rank on tooltips
Hover an item you can craft, in your bags, at the auction house or in a chat link, and its tooltip gets a **Craft Rank** line: the highest rank each of your characters can make it at with the top quality of every material.

- One line for each character that knows the recipe, in its class color, best rank first. Characters on another realm show their realm too. Switch to **this character only** in the options for a single line.
- Deleted, renamed or moved a character? Forget it in the options (**Saved characters: Forget...**).

- **Max rank** in green when you can make it at the top rank, or **Rank 3 of 5** in orange when you can't yet.
- If concentration reaches a higher rank, that rank is shown, with the concentration it takes, e.g. **Max rank (38 concentration)**. You can hide the concentration in the options.
- **with optional reagents:** a second line under it when optional reagents make the item harder to craft, like the ones that raise its item level. It shows the best rank with the one that makes it hardest in each optional slot, at its top rank. Only shown when it's lower than without them, or takes more concentration.
- Finishing materials aren't counted.
- Only for recipes that come in ranks.
- It updates each time you open your profession window, so after you gain skill or spend specialization points, open the window once on that character. A character shows up after you've opened its profession window once.

## Options
Click the gear on the panel (or Craft Profit options in the gear menu under the Patron tab's list), type `/craftprofit`, or go to **Esc → Options → AddOns → Craft Profit**.

| Option | What it does |
|---|---|
| Show on the crafting page / on crafting orders | Turn the panel on or off for each page. |
| Lock panel position | Stops the panel from being dragged. |
| Panel size | Size of the whole panel, 60% to 150%. |
| Panel position: Reset | Puts the panel back next to the profession window. |
| Show amounts down to | Gold, silver (default) or copper. |
| Show Craft Profit on the Patron tab | Materials, Rewards, Profit and Actions columns, the shopping buttons and the footer on the Patron tab. On by default; off gives back Blizzard's own columns. |
| Patron orders: Spend concentration on | Most profit (default): the most gold per concentration point first. Knowledge first: orders that reward profession knowledge first, then by profit. Don't use concentration: patron orders never spend it, and the ones that need it get no buttons. Also in the gear menu under the Patron tab's list. |
| Patron orders: Optimize concentration | Orders that need concentration use the qualities that need the least of it, the cheapest of those. Off by default. Also in the gear menu under the Patron tab's list, on the crafting order form and on the crafting page. |
| Show the Shopping list button | The Shopping list row, and on the Patron tab Add profitable, Add all and the cart buttons. On by default; hidden anyway without Auctionator or TSM. |
| Shop with | With Auctionator and TSM both installed: Auctionator shopping list (default) or TSM search to copy. Also at the bottom of the Shopping list menu and in the gear menu under the Patron tab's list. |
| One shopping list per character / per profession | On by default. Either or both split the shopping list, e.g. Thrall - Blacksmithing. With both off, it's called Crafting. |
| Check off what you get | On by default. Materials come off the Auctionator shopping list as you get them: bought, looted, from the mailbox or crafted. |
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
- After an update, a What's New window shows what changed since the version you had.
