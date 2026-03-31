# Playability Verification

## Host-Side Verification Method

- Browser automation used Playwright against `http://127.0.0.1:4174/`.
- Evidence source: `host-playwright-verification.json`.
- Visual artifacts: `host-initial.png` and `host-after-restart.png`.

## Verified Behaviors

- Initial page load succeeded with title `game-2048`.
- The initial board contained exactly 2 non-zero tiles.
- The controls text showed `Arrows / WASD`.
- A valid move spawned a new tile.
- A merge increased the score.
- Autoplay reached a real game-over state.
- Restart cleared the overlay and reset the board to 2 spawned tiles.

## Recorded Results

- `spawnVerified: true`
- `mergeVerified: true`
- `gameOverReached: true`
- `autoplaySteps: 248`
- Pre-restart score: `3092`
- Best tile reached during the recorded game-over state: `256`

## Deterministic Checks Captured

- `ArrowUp` moved the board from 2 to 3 non-zero tiles while keeping score at `0`.
- `ArrowRight` moved the board from 3 to 4 non-zero tiles while keeping score at `0`.
- `ArrowDown` moved the board from 4 to 5 non-zero tiles while keeping score at `0`.
- `ArrowLeft` produced a merge and increased score from `0` to `4`.

## Conclusion

- The generated application is not just visible; it is actually playable under keyboard input.
- The acceptance bar for move, merge, spawn, score, game-over, and restart behavior passed on the host machine.
