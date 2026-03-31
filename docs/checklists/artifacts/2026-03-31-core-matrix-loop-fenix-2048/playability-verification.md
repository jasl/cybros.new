# Playability Verification

## Host-Side Verification Method

- Browser automation used Playwright against `http://127.0.0.1:4174/`.
- Evidence source: `host-playwright-verification.json`.
- Visual artifacts: `host-initial.png` and `host-after-restart.png`.

## Verified Behaviors

- Initial page load succeeded with title `game-2048`.
- The initial board contained exactly 2 non-zero tiles.
- The controls text showed `Controls: Arrow keys or W A S D`.
- A valid move produced a real merge and increased score.
- A non-merge follow-up move spawned a new tile.
- Autoplay reached a real game-over state with status text `Game over`.
- Restart reset the score to `0` and returned the board to 2 spawned tiles.

## Recorded Results

- `spawnVerified: true`
- `mergeVerified: true`
- `gameOverReached: true`
- `autoplaySteps: 243`
- Pre-restart score: `2804`
- Best tile reached during the recorded game-over state: `256`

## Deterministic Checks Captured

- `ArrowUp` moved the board from 2 to 2 non-zero tiles while score changed from 0 to 4.
- `ArrowDown` moved the board from 2 to 3 non-zero tiles while score stayed at 4.

## Conclusion

- The generated application is not just visible; it is actually playable under keyboard input.
- The acceptance bar for move, merge, spawn, score, game-over, and restart behavior passed on the host machine.
