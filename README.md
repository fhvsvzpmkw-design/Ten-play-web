# Ten Play Web

A browser port of `MASTER_v1.9.1_PRO_BASE`, the SwiftUI 10-play 9/6 Jacks or Better trainer.

## Current scope

- 10-play Jacks or Better deal/draw loop
- 9/6 paytable with five-coin royal bonus
- Trainer and Casino display modes
- Monte Carlo hold suggestions for all 32 hold masks
- Exact-on-demand evaluation for visible suggestions drawing three cards or fewer
- Credit, wager, payout, and session RTP tracking
- Responsive phone, tablet, and desktop layout
- Device-local session persistence

The original Swift source is retained in `reference/MASTER_v1.9.1_PRO_BASE.swift` as the behavioral baseline. The strategy and flush hierarchy remain marked for a dedicated verification pass, matching the deferred verification note in v1.9.1.

See `PORT_NOTES.md` for the Swift-to-web mapping and the two integrity corrections made during the port.

## Run locally

Serve the repository with any static file server, then open `index.html`. For example:

```bash
python3 -m http.server 8080
```

Open `http://localhost:8080`.

## Validate

No package installation is required.

```bash
npm run validate
```

## Deployment

The included GitHub Pages workflow enables Pages and publishes the repository root whenever `main` is updated.
