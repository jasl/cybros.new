# Playability Verification

Host-side browser verification was executed against:

- `http://127.0.0.1:4174/`

Verification artifacts:

- `host-playwright-verification.json`
- `host-playability.png`

## Verified Behaviors

- Page loaded successfully from the host preview server.
- Keyboard play worked with real browser input.
- Direction produced a valid board change: `ArrowLeft`
- Direction produced a valid board change: `ArrowUp`
- Direction produced a valid board change: `ArrowRight`
- Direction produced a valid board change: `ArrowDown`
- Merge behavior was observed.
- Score increased on merge.
- A new tile appeared after a valid move.
- A full game-over state was reached through real key presses.
- Restart reset the score to `0`.
- Restart reset the board to exactly two starting tiles.

## Observed Run Details

- Initial board had `2` tiles.
- During automated host play, score reached `3292`.
- Pre-restart state showed `Game over` with a full `4x4` board.
- Post-restart state returned to `Keep going` and `2` starting tiles.

## Host Verification Commands

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048/dist
python3 -m http.server 4174 --bind 127.0.0.1
npm install --no-save @playwright/test@1.59.1
npx playwright install chromium
npx playwright test host-playability.spec.cjs --workers=1 --reporter=line
```

Browser validation used Playwright on the host against the platform-independent `dist/` output.
