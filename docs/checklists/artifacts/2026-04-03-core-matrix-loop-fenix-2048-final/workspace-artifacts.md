# Workspace Artifacts

- Mounted host workspace root:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`
- Final application path:
  - `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048`
- Final source tree includes:
  - `dist/assets/index-BrESJGSo.css`
  - `dist/assets/index-D5QEScib.js`
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
  - `src/game.test.ts`
  - `src/game.ts`
  - `src/index.css`
  - `src/main.tsx`
  - `src/test/setup.ts`
  - `tsconfig.app.json`

## Host-Side Commands

Primary host usability verification uses the exported `dist/` output:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/tmp/fenix/game-2048/dist
python3 -m http.server 4174 --bind 127.0.0.1
```

Source portability diagnostics remain separate and may require reinstalling host-native dependencies:

Because the mounted workspace contained container-built dependencies, source-portability diagnostics first normalized those artifacts:

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
```

## Run URL

- Preview URL:
  - `http://127.0.0.1:4174/`

Host preview reachability is recorded separately in `workspace-validation.md` and `host-preview.json` when available.
