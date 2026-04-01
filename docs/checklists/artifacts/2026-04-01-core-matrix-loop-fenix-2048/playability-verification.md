# Playability Verification

## Host-Side Verification Method

- Browser automation used host-side Playwright against `http://127.0.0.1:4174/`.
- Evidence source: `host-playwright-verification.json`.
- Visual artifact: `host-playwright-verification.png`.

## Verified Behaviors

- Initial page load succeeded.
- The initial board contained exactly 2 non-zero tiles.
- Real movement was observed in all four directions: `up`, `down`, `left`, and `right`.
- A valid move produced a real merge and increased score.
- A later valid move clearly spawned a new tile.
- Restart reset the score to `0` and returned the board to 2 spawned tiles.
- Autoplay reached a real `Game over` state under keyboard input.

## Recorded Results

- `spawn_verified: true`
- `merge_verified: true`
- `score_after_merge: 8`
- `restart_verified: true`
- `game_over_verified: true`
- `move_attempts: 314`

## Conclusion

- The generated application is not just visible; it is actually playable under host-side keyboard input.
- The acceptance bar for move, merge, spawn, score, restart, and game-over behavior passed on the host machine.
