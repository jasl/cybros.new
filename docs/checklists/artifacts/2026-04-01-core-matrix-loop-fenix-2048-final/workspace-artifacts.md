# Workspace Artifacts

- Mounted host workspace root:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`
- Final application path:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048`
- Final source tree includes:
  - `src/App.tsx`
  - `src/game.ts`
  - `src/game.test.ts`
  - `package.json`
  - `vite.config.ts`
  - built `dist/`

## Host-Side Commands

Because the mounted workspace contained container-built `node_modules`, host-side verification first removed those platform-specific artifacts and reinstalled dependencies on macOS:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048
rm -rf node_modules package-lock.json
npm install
```

Host-side verification commands:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048
npm test
npm run build
npm run preview
```

## Run URL

- Preview URL:
  - `http://127.0.0.1:4173/`

The preview process stayed reachable on the host during browser verification.
