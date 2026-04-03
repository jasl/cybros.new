# Workspace Artifacts

- Mounted host workspace root:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`
- Final application path:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048`
- Final source tree includes:
  - `dist/assets/index-BRmAR4X6.js`
  - `dist/assets/index-BruX-Qfu.css`
  - `dist/index.html`
  - `index.html`
  - `package.json`
  - `src/App.tsx`
  - `src/game.test.ts`
  - `src/game.ts`
  - `src/main.tsx`
  - `src/styles.css`
  - `src/test/setup.ts`
  - `tsconfig.app.json`
  - `tsconfig.json`
  - `vite.config.ts`

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
