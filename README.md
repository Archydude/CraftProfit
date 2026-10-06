# Craft Profit

A small panel next to your profession window that tells you, in gold, whether a craft or a crafting order makes or loses money.

- **Crafting page:** what the item sells for, minus the 5% auction house cut, minus your materials.
- **Crafting orders:** the commission you receive (after the consortium cut), minus the materials **you** supply, plus any sellable patron rewards.

- **Procs:** when a craft procs multicraft or resourcefulness, the bonus gold pops up over the Profit line with a coin sound, a **Procs** section lists the extra items and returned materials with their value, and Profit/Loss changes to what that craft really made. It goes back to the normal forecast on your next craft without a proc, or when you pick another recipe.

- **Session total:** under Profit/Loss, what all your crafts made since you logged in on this character (a `/reload` keeps it). Crafts without a price, like enchants, aren't counted.

It's a lightweight alternative to CraftSim if you only want the money question answered. It doesn't simulate procs in advance; it shows you the gold when they happen.

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

- **Crafting page:** the panel updates the material cost, asks the game which quality the item would come out at, and re-prices the sale.
- **Crafting orders:** works on the materials you supply. The panel shows the quality you'd get and warns in red when it's below the order's minimum quality, so you can see whether a cheaper quality still does the job.

- **Right-click** a material to put it back, or click the blue note at the bottom to reset all of them.
- Only the panel changes. Your real craft still uses what's in Blizzard's form, and procs and the session total always count the real craft.
- Picked qualities reset when you choose another recipe.
- If the game can't predict the quality for a mix (for example with materials you don't own), the panel says so and keeps the form's quality for the sale price.

## Options
Click the gear on the panel, type `/craftprofit`, or go to **Esc → Options → AddOns → Craft Profit**.

| Option | What it does |
|---|---|
| Show on the crafting page / on crafting orders | Turn the panel on or off for each page. |
| Lock panel position | Stops the panel from being dragged. |
| Panel size | Size of the whole panel, 60% to 150%. |
| Panel position: Reset | Puts the panel back next to the profession window. |
| Show amounts down to | Gold, silver (default) or copper. |
| Animate multicraft & resourcefulness procs | On by default. |
| Coin sound on procs | On by default. |
| Show this session's total | On by default. |
| Session total: Reset | Starts the session total from zero. |
| Price addon | Automatic (TSM, then Auctionator for anything TSM has no price for), TSM only, or Auctionator only. |
| TSM price for materials / crafted items | Market value (default), lowest auction right now, historical price or region market average. |
| Use vendor price for vendor items | On by default. |
| Subtract auction house cut (5%) | On by default. |

## Notes
- With Auctionator, prices come from your own auction house scans. With TSM, the TSM desktop app keeps them up to date for you.
- Craft Profit reads some of Blizzard's profession window data directly, so a big Blizzard update to that window may need a patch here.
