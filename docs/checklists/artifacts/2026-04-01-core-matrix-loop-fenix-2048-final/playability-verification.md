# Playability Verification

Host-side browser verification was executed against:

- `http://127.0.0.1:4173/`

Verification artifacts:

- `host-playwright-verification.json`
- `host-playability.png`

## Verified Behaviors

- Page loaded successfully from the host preview server.
- Keyboard play worked with real browser input.
- All four directions produced valid board movement:
  - `ArrowLeft`
  - `ArrowUp`
  - `ArrowRight`
  - `ArrowDown`
- Merge behavior was observed.
- Score increased on merge.
- A new tile appeared after valid non-merge moves.
- A full game-over state was reached through real key presses.
- Restart reset the score to `0`.
- Restart reset the board to exactly two starting tiles.

## Observed Run Details

- Initial board had `2` tiles.
- During automated host play, score reached `3028`.
- Pre-restart state showed `Game over` with a full `4x4` board.
- Post-restart state returned to the normal status line and `2` starting tiles.

## Host Verification Commands

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048
npm test
npm run build
npm run preview
```

Browser validation used Playwright on the host after reinstalling host-native dependencies.
