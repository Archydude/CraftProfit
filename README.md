# Craft Profit

A lightweight addon: one small panel next to your profession window that tells you, in gold, whether a craft or a crafting order makes or loses money.

- **Crafting page:** what the item sells for, minus the 5% auction house cut, minus your materials. With nothing to sell (no auction price, an enchant, a recraft), it's a loss of what the materials cost.
- **Crafting orders:** the commission you receive (after the consortium cut), minus the materials **you** supply, plus any sellable patron rewards.

- **Procs:** when a craft procs multicraft or resourcefulness, a **Procs** section lists the extra items and returned materials with their value, and **This craft made** under them says what that craft really made; the bonus gold pops up from it with a coin sound. It goes away on your next craft without a proc, or when you pick another recipe. The profit lines below it stay the forecast.

- **Expected profit:** the panel's main line, at the top, is what a craft makes on average once multicraft and resourcefulness are counted, with **Without procs** under it: what it makes when neither procs. Your chances come from the game; how big your procs are, Craft Profit learns from your own crafts (until it has 10 procs of a kind, it uses typical values). Hover it for each proc's chance, size and what it adds.

- **Crafting strategy:** pick what to craft: the highest rank you can make (default), the most profit, or the cheapest materials. One click, or a checkbox on the crafting page and the order form, puts its materials in; missing materials and the shopping list follow it too. On an order, the cheapest materials that reach its minimum quality.

- **Best crafts:** every recipe you know in a profession, ranked by profit, with what each could make in a day, how many are listed and how many you've sold.

- **Shopping list:** adds what you're short of, for one or more crafts or for every patron order at once, to an Auctionator shopping list, or as a TSM search to copy. The Auctionator list checks materials off as you get them.

- **Session total:** under Profit/Loss, what all your crafts made since you logged in on this character (a `/reload` keeps it), including orders crafted from the Patron tab, where it also shows under the order list. Crafts whose item has no sale price, like enchants and treatises, count as a loss of what their materials cost, less what resourcefulness gives back. Click it to reset it to zero. After 5 crafts it also shows your **luck**: how much more (or less) your procs made than expected, like **Luck +14%**.

- **Minimap button:** opens your profession window on the Best crafts list; hover for this session's total.

- **Best rank on tooltips:** an item you can craft shows the highest rank you can make it at with top-quality materials, anywhere you see its tooltip.

It stays light: nothing runs until you open your profession window, apart from noting your auction sales when you open your mailbox. Procs are counted as an average, always shown next to the profit without them.

Requires **TradeSkillMaster** or **Auctionator** for prices. Built for WoW Midnight 12.1.

## Install
Copy the `CraftProfit` folder to `World of Warcraft\_retail_\Interface\AddOns\` and restart the game.

## Use
Open your profession and pick a recipe, or open a crafting order. The panel appears to the right of the window.

The panel reads top to bottom: the expected profit or loss, what comes in (the sale price, or an order's commission and rewards), your materials with what they cost in all, then one line with this session's total and luck. Hover the **i** at the end of that line for the notes on how the numbers were worked out. Notes you need to see, like materials without a price or old prices, stay in sight.

- Materials are priced at the quality you actually put in the form. If a slot is empty (you don't own the material), or the form holds another quality because you're short of the one your crafting strategy picks (see below), it's priced at the strategy's quality, so the profit is for what you'd craft once you've bought it. On an order, it's priced at the quality the Patron tab picks for the order. A material you're short of has a cart button: click it to shop for just that material.
- The sale price follows the quality you'll get, including concentration if you turn it on.
- A lower rank is never worth more than a better one: when rank 3 is listed higher than rank 5 sells for, nobody buys it at that price, so it's priced as rank 5 sells and the panel's notes say so. The Best crafts list counts it the same way.
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

**Cheaper rank to buy:** on a crafting order, when the form uses a rank you own and buying another rank comes out cheaper, a blue line under that material says how much it saves, e.g. **[rank 1] saves 2g 40s**. What you own counts at what it would sell for after the 5% auction house cut, so the line only shows when buying really comes out ahead, and only for a rank that still meets the order's minimum quality on its own, without an optional or finishing reagent that raises your skill. It only suggests the rank the Patron tab picks for the order, so it never goes against **Optimize Concentration**. Click it to use that rank: the panel and the shopping list switch to it. Hover it for the numbers.

### Crafting strategy
What the crafting page crafts. Set it with the **Crafting strategy** dropdown on the panel (under your materials, when a recipe is open), at the bottom of the Best crafts list, or in the options:

- **Highest rank, cheapest materials** (default): the highest rank you can make, with the cheapest materials that reach it. A lower rank is never picked when a better one is in reach, even if it's listed for more or the better rank's materials cost more: buyers want the best rank.
- **Most profit:** the rank that makes the most gold after what its materials cost, with the cheapest materials that make it. With no sale price for the item at any rank, the cheapest materials that keep the rank it comes out at now.
- **Cheapest materials:** the cheapest materials, whatever rank they make. For skill-ups, first crafts and knowledge.

It picks the materials for the blue row and **Use Craft Profit Reagents** (below), prices the materials you're missing, decides which qualities the shopping list buys, and ranks the Best crafts list. Concentration stays as you set it in the form: with it on, the rank it reaches counts. What you own counts at what it would sell for. Patron orders keep their own rule (below).

**The blue row:** when the form holds other materials than Craft Profit would use, a blue row under the materials puts them in Blizzard's form with a click. Hover it to see what it puts in.

- **On the crafting page:** **Use Craft Profit materials**, the crafting strategy's materials. It says how much more they make, or which rank they make instead (e.g. rank 5 instead of rank 4, even when that costs more).
- **On a crafting order:** **Use the most profitable materials**, the cheapest qualities that still reach the order's minimum quality, the same materials the Patron tab prices each order with. If reaching the minimum quality takes concentration, it turns that on too.
- A material you don't have enough of stays as it was, and chat says what to buy.

**Use Craft Profit Reagents:** a checkbox on the crafting order form and the crafting page, above Blizzard's **Use Best Quality Reagents**. While it's on, every order or recipe you open gets Craft Profit's materials put in by itself: the crafting strategy's on the crafting page, the most profitable ones on an order. A slot you change afterwards stays as you set it. Unticking it puts back the materials Blizzard picks by itself, and turns concentration back off if the checkbox turned it on. Only one of the two checkboxes can be on: checking one unchecks the other. It's the same setting on both pages. It shows wherever Blizzard's checkbox does, on orders and recipes whose materials come in qualities. Above it, **Optimize Concentration** (see Patron orders below) works the same way: on the crafting page, with concentration on, it picks the qualities that reach the crafting strategy's rank with the least concentration.

### Shopping list
Under your materials there's a **Shopping list** button. It shows a count when you're short of materials for one craft; hover it to see what's missing.

**Click** it to add what you're missing for one craft. **Shift-click** it to open a menu:

- **For 1 / 5 / 10 crafts:** adds what you're missing for that many crafts, with the amount and quality, to an Auctionator shopping list (see Separate lists below). Each line shows how many items it would add. Open the list in Auctionator's Shopping tab at the auction house.
- **Other amount...:** type any number of crafts. The last number you typed stays in the menu until you log out or `/reload`.
- **Clear shopping list.**

Adding again (or on another recipe) adds to the amounts already on the list. Vendor-sold and soulbound materials are listed in chat instead. Every quality you own counts toward a material, and the cheapest quality is the one added. On the crafting page, when the form can't make the crafting strategy's rank (or a slot is empty), the list adds the qualities the strategy picks instead, so what you buy makes that rank. On a crafting order whose minimum quality the form doesn't reach, the list adds the qualities that do reach it instead, the same ones the Patron tab picks. To buy a specific quality, click the material to pick it first (see above).

Shortcut: **Ctrl-click** clears the list, without the menu.

**Checked off as you get them:** materials come off the list as they arrive: bought at the auction house, looted, taken from the mailbox or crafted. (Auction house items that aren't commodities come by mail, so they're checked off once you take them out.) Chat says what came off, and when the list is done. Only what Craft Profit added is checked off: lines you add yourself in Auctionator stay. Moving things between your bags, bank and warband bank doesn't count. Turn off **Check off what you get** in the options to keep the list until you clear it.

**Just one material:** click the cart next to a material you're short of, or **Shift-click** the material, to add only what you're missing of it, for one craft. Pick a quality first by clicking it, and that quality is what gets added. With TSM, you get a search for just that material.

**Separate lists:** each character and profession gets its own list, like **Thrall - Blacksmithing**. Turn off **one shopping list per character** or **per profession** in the options to share lists instead; with both off, the list is called **Crafting**. Lists from before 1.19.0, named **Craft Profit - ...**, are moved to the new names the next time you log in, along with what's on them.

**TSM without Auctionator:** the button says **Copy TSM search** instead, with the same menu. Pick an amount and a box shows a search, already selected: press Ctrl+C and paste it into the search box on TSM's Shopping tab. It searches for exactly the ranks you're missing and stops at the amounts you need. With neither Auctionator nor TSM, the button is hidden.

**Both installed?** Pick **Shop with: Auctionator shopping list** (default) or **TSM search to copy** at the bottom of the menu, in the gear menu at the bottom of the Patron tab, or in the options.

You can hide the Shopping list button and the Patron tab's shopping buttons in the options. The options also have a **Clear** button for the list.

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

**Don't use concentration:** the third choice for which orders get concentration. Patron orders then never spend it: an order that only reaches its minimum quality with concentration shows its profit in grey and **No concentration** under Materials, with no cart and no craft button, and Add profitable and Add all skip it. On its order form, Use Craft Profit Reagents and the blue row leave the materials alone. Orders that reach their minimum without concentration work as usual, and the crafting page isn't affected.

**Optimize concentration:** in the gear menu under the list, also on the crafting order form and the crafting page (above Use Craft Profit Reagents) and in the options. With it on, an order that needs concentration uses the material qualities that need the least of it, and the cheapest of those, so your concentration covers more orders. The materials cost more. Use Craft Profit Reagents and the blue row on the order form pick the same materials.

Turn off **Show Craft Profit on the Patron tab** in the options to get Blizzard's own columns back.

### Best crafts
Click **Best crafts** at the top of the panel, next to its gear (on the crafting page, or on a crafting order, where it goes back to your recipes first), or type `/craftprofit best`. A list opens over the recipe details with every recipe you know in the profession shown (Midnight Blacksmithing, say), most profitable first. It works out each recipe for a few seconds after it opens, and shows how far it's got at the bottom.

- **Expected** (or **Profit**): what one craft makes after the 5% auction house cut, at the rank your crafting strategy picks (without concentration), with the materials it picks: the same ones the crafting page would use. With **Count multicraft and resourcefulness** on (the default), it's what a craft makes on average with procs, and the list ranks by it; off, the column is **Profit**, without them. Its quality icon is after the name. Recipes whose item has no auction price at the rank you'd make say **No price**, in grey, at the bottom.
- **Gold/day:** roughly what the recipe could make in a day: the profit on each item times how many sell per day, counting 20 a day at most. So a recipe with a big profit that hardly sells stops looking better than one that sells all day. It's for comparing recipes, not a promise: with TSM it counts sales across your whole region, and you'd only get a share of them; without TSM, your own sales from the last 14 days. Recipes that lose gold or haven't sold show **-**. The list still opens sorted by profit; click the header to sort by it.
- **Listed:** how many were up for sale the last time Auctionator saw them, in grey when that was 3 days ago or more. Needs Auctionator; without it, **-**.
- **Sells/day** (with TSM): how many sell per day across your region, on average.
- **You sold** (without TSM, in place of Sells/day): how many your characters sold on the auction house in the last 14 days, counted from the auction house's mail each time you open your mailbox. It starts counting with this version, so it fills in over the first two weeks. With TSM, it's in each row's tooltip instead.
- **Eye:** ignores the recipe (see below).
- **Cart:** the shopping list button, as on the panel: click for what's missing for one craft, Shift-click to pick how many crafts. It buys the qualities the row is priced with.
- **Icons** after the name: the rank it's priced at, the first-craft icon when crafting it the first time gives profession knowledge, and a watch when it's on cooldown. A long name is cut short so they always show.

**Hover a row** for the sale price, each material and its price, the profit, and what concentration would add (e.g. **+95g for 38 concentration, 2g 50s per point**). For items with ranks, each rank's price and how many of it are listed, so a rank nobody buys stands out.

**Click a row** to open its recipe. With **Use Craft Profit Reagents** on, its materials go straight in. Click **Best crafts** again to go back to the recipe.

Click a column header to sort by it; click again to reverse. Recipes without a value for that column stay at the bottom either way. Type in the search box to find a recipe.

**Filter:** the button next to the search box.
- **Profitable only** hides the recipes that lose gold or have no price.
- **Count multicraft and resourcefulness** switches the first column between Expected and Profit (also in the options).
- **Show:** a checkbox for each kind of item the profession makes, with how many: **Gear** (weapons, armor and profession tools), **Decor**, **Materials** (reagents, trade goods and gems), **Enchants and kits**, **Consumables**, **Bags** and **Other**. **Show all** and **Hide all** set them all at once.
- **Show ignored recipes** shows the recipes you ignored (below), in grey and marked **ignored**. **Stop ignoring all** brings back every ignored recipe of the profession shown.
- The list remembers the filter. The small red button on it puts everything back (ignored recipes stay ignored).

**Ignore a recipe:** click the eye at the end of its row (or right-click the row) to hide it from the list, for when an item is priced far too high for no reason. With Show ignored recipes on, an ignored row has an undo arrow there instead: click it to stop ignoring it. The ignore list is the same for all your characters.

- Concentration isn't used for the ranking; the row's tooltip shows what it would add.
- Only this character's recipes: the game only says how a craft turns out for the character whose profession window is open.
- It works out the list again when you gain skill, spend specialization points or change profession gear while it's open.

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

## Minimap button
- **Click:** opens the profession window of the profession you opened last, on its Best crafts list. Click again to close the list.
- **Right-click:** a menu to open any of your professions' Best crafts, switch the crafting strategy, or open the options.
- **Hover:** this session's total and your luck.
- Drag it around the minimap. It's also in the minimap's addon menu, and works with minimap button collectors.
- Hide it with **Show minimap button** in the options, or type `/craftprofit minimap` (type it again to bring it back).

## Options
Click the gear on the panel (or Craft Profit options in the gear menu under the Patron tab's list), type `/craftprofit`, or go to **Esc → Options → AddOns → Craft Profit**. The main page has what to craft and where prices come from; click the **+** next to Craft Profit for the other pages.

**Craft Profit**

| Option | What it does |
|---|---|
| Crafting strategy | What the crafting page crafts: Highest rank, cheapest materials (default), Most profit, or Cheapest materials. Also at the bottom of the Best crafts list. |
| Count multicraft and resourcefulness | On by default. The Best crafts list ranks by what crafts make on average with procs, and Most profit picks ranks that way. Also in the Best crafts list's Filter menu. |
| Show minimap button | On by default. Also `/craftprofit minimap`. |
| Price addon | Automatic (TSM, then Auctionator for anything TSM has no price for), TSM only, or Auctionator only. |
| TSM price for materials / crafted items | Market value (default), lowest auction right now, historical price or region market average. |
| Remind me to scan the auction house | On by default. With Auctionator prices: a chat reminder at the auction house after a day, and a notice over the Best crafts list after 3 days. |
| Use vendor price for vendor items | On by default. |
| Subtract auction house cut (5%) | On by default. |

**Panel**

| Option | What it does |
|---|---|
| Show on the crafting page / on crafting orders | Turn the panel on or off for each page. |
| Panel size | Size of the whole panel, 60% to 150%. |
| Show amounts down to | Gold, silver (default) or copper. |
| Lock panel position | Stops the panel from being dragged. |
| Panel position: Reset | Puts the panel back next to the profession window. |
| Animate multicraft & resourcefulness procs | On by default. |
| Coin sound on procs | On by default. |
| Show this session's total | On by default. |
| Session total: Reset | Starts the session total from zero. |

**Shopping list**

| Option | What it does |
|---|---|
| Show the Shopping list button | The Shopping list button under your materials, and on the Patron tab Add profitable, Add all and the cart buttons. On by default; hidden anyway without Auctionator or TSM. |
| Shop with | With Auctionator and TSM both installed: Auctionator shopping list (default) or TSM search to copy. Also at the bottom of the Shopping list menu and in the gear menu under the Patron tab's list. |
| One shopping list per character / per profession | On by default. Either or both split the shopping list, e.g. Thrall - Blacksmithing. With both off, it's called Crafting. |
| Check off what you get | On by default. Materials come off the Auctionator shopping list as you get them: bought, looted, from the mailbox or crafted. |
| Auctionator shopping list: Clear | Empties the shopping list. With one list per profession and no profession window open, it empties all this character's profession lists. |

**Patron orders**

| Option | What it does |
|---|---|
| Show Craft Profit on the Patron tab | Materials, Rewards, Profit and Actions columns, the shopping buttons and the footer on the Patron tab. On by default; off gives back Blizzard's own columns. |
| Spend concentration on | Most profit (default): the most gold per concentration point first. Knowledge first: orders that reward profession knowledge first, then by profit. Don't use concentration: patron orders never spend it, and the ones that need it get no buttons. Also in the gear menu under the Patron tab's list. |
| Optimize concentration | Orders that need concentration use the qualities that need the least of it, the cheapest of those. Off by default. Also in the gear menu under the Patron tab's list, on the crafting order form and on the crafting page. |

**Tooltips**

| Option | What it does |
|---|---|
| Show the best rank you can craft | The **Craft Rank** line on item tooltips. On by default. |
| Show it for | All your characters (default) or this character only. |
| Show the concentration it takes | Adds the concentration when the best rank needs it. On by default. |
| Saved characters: Forget... | Pick a character you deleted, renamed or moved to take it off Craft Rank tooltips. |

## Notes
- With Auctionator, prices come from your own auction house scans. Once Auctionator's last scan is over a day old, the panel's and the Best crafts list's footers say so in red ("last scan 2 days ago"), and opening the auction house reminds you in chat to run a full scan. Over 3 days old, opening the Best crafts list shows a notice in the middle of the list, once a session. Turn the reminders off with **Remind me to scan the auction house** in the options. With TSM, the TSM desktop app keeps them up to date for you. With Auctionator, the panel's notes say how old its oldest price is (**seen today**, or **oldest 4 days ago**, in red and in sight at the bottom of the panel once it's 3 days or more), and each material's tooltip says when Auctionator last saw it. Visit the auction house to refresh them.
- A big Blizzard update to the profession window may need a Craft Profit update too.
- After an update, a What's New window shows what changed since the version you had.
