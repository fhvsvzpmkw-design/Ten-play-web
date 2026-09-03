# Swift v1.9.1 to Web Port Notes

## Directly preserved

| Swift area | Web module |
| --- | --- |
| `Card`, `Suit`, and `Deck` | `src/cards.js` |
| `HandEvaluator`, paytable, payout, winning masks | `src/engine.js` |
| `EVEngine` and `Strategy` | `src/strategy.js` |
| Detached EV task | `src/ev-worker.js` Web Worker |
| `PokerTrainerViewModel` and `ContentView` | `src/app.js`, `index.html`, and `styles.css` |

The browser version retains the 1–5 coin schedule, ten hands per round, MC-first suggestions, exact-on-demand behavior, Trainer/Casino status modes, best-result ordering, and the distinct Trips and Two-Pair strategy tiers added in v1.9.1.

## Port integrity corrections

1. **The recommended hold now matches the displayed BEST row.** The Swift source selected the highest raw Monte Carlo hold before independently sorting the visible rows through the strategy hierarchy. Those could disagree. The web port uses the first hierarchy-ranked row for both the automatic hold and the BEST display.
2. **The wager locks after Deal.** The Swift controls allowed the coin value to change after the ten-hand wager had already been deducted, which could make the recorded wager and eventual payout use different coin values. The web controls remain locked until the round finishes.

## Deliberately deferred

The source header explicitly deferred flush verification. The broader hand-strategy hierarchy also needs a dedicated comparison against an authoritative 9/6 Jacks or Better strategy before the trainer should be treated as mathematically certified. The current web version faithfully ports those strategy detectors and labels without silently replacing them.
