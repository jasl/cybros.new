# Workspace Artifacts

- Mounted host workspace root:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`
- Final application path:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048`
- Final source tree includes:
  - `dist/assets/index-BNuLcDp7.css`
  - `dist/assets/index-DsCM8Eip.js`
  - `dist/favicon.svg`
  - `dist/icons.svg`
  - `dist/index.html`
  - `index.html`
  - `package.json`
  - `public/favicon.svg`
  - `public/icons.svg`
  - `src/App.css`
  - `src/App.tsx`
  - `src/assets/hero.png`
  - `src/assets/react.svg`
  - `src/assets/vite.svg`
  - `src/components/GameBoard.tsx`
  - `src/components/ScorePanel.tsx`
  - `src/game/logic.test.ts`
  - `src/game/logic.ts`
  - `src/game/types.ts`
  - `src/index.css`

## Host-Side Commands

Because the mounted workspace contained container-built dependencies, host-side verification first normalized those artifacts:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048
rm -rf node_modules dist coverage
npm install
```

Host-side verification commands:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048
npm test
npm run build
npm run preview -- --host 127.0.0.1 --port 4174
```

## Run URL

- Preview URL:
  - `http://127.0.0.1:4174/`

The preview process stayed reachable on the host during browser verification.
