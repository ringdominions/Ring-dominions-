# 🥊 Ring Dominion — Arena Fight Protocol

Ring Dominion is a browser-based, single-file arena fighting game. Pick a champion, climb the tournament ladder, and claim the chain — all running client-side with plain HTML, CSS, and JavaScript (no build step required).

[![Website](https://img.shields.io/badge/play-online-brightgreen?style=for-the-badge)](https://blackbullagents.github.io/Ring-dominions-/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)
[![X Follow](https://img.shields.io/badge/follow-@Devringdominion-1DA1F2?style=for-the-badge)](https://x.com/Devringdominion)

[🎮 Play Online](https://blackbullagents.github.io/Ring-dominions-/) · [🐛 Report Bug](.github/ISSUE_TEMPLATE/bug_report.md) · [💡 Request Feature](.github/ISSUE_TEMPLATE/feature_request.md)

---

## 📌 About

Ring Dominion is a fast-paced, ranked PvP arena fighter that runs entirely in the browser. No installs, no accounts required to play — just open `index.html` (or the GitHub Pages link) and start fighting.

### ✨ Features

| Feature | Description |
|---|---|
| 🥋 **Ranked PvP** | Climb a tiered ladder from Rust Division to the top rank |
| 🏆 **Global Ladder** | Face increasingly tough opponents as you rank up |
| 🎨 **Cyber Arena** | Stylized neon/HUD-driven combat presentation |
| ⚡ **Single-file build** | The entire game ships as one self-contained `index.html` |
| 📱 **Touch-friendly** | Playable on mobile and desktop |

---

## 🚀 Quick Start

### Option 1 — Play Online

👉 Open [`index.html`](index.html) directly in a browser, or visit the GitHub Pages deployment once enabled (see below).

### Option 2 — Run Locally

```bash
# Clone the repository
git clone https://github.com/blackBullAgents/Ring-dominions-.git
cd Ring-dominions-

# Just open it — no build step needed
open index.html   # macOS
# or
start index.html  # Windows
# or
xdg-open index.html # Linux
```

### Option 3 — Serve Locally (recommended for full functionality)

```bash
python3 -m http.server 8000
# then visit http://localhost:8000
```

---

## 🌐 Enable GitHub Pages (optional)

1. Go to **Settings → Pages** in this repository.
2. Under **Build and deployment**, set **Source** to `Deploy from a branch`.
3. Choose the `main` branch and `/ (root)` folder.
4. Save — your game will be live at `https://<your-username>.github.io/Ring-dominions-/`.

A ready-made GitHub Actions workflow is also included at [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) if you'd rather deploy via Actions.

---

## 🗂️ Project Structure

```
Ring-dominions-
├── .github/
│   ├── ISSUE_TEMPLATE/       # Bug report & feature request templates
│   └── workflows/            # GitHub Actions (Pages deploy)
├── docs/                     # Extra notes / design docs
├── .gitignore
├── .nojekyll
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE
├── README.md
├── SECURITY.md
└── index.html                # The entire game (HTML + CSS + JS)
```

---

## 🤝 Contributing

Contributions are welcome!

1. **Fork** this repository
2. **Create** your branch: `git checkout -b feat/your-feature`
3. **Commit**: `git commit -m 'feat: add your feature'`
4. **Push**: `git push origin feat/your-feature`
5. **Open a Pull Request**

See the full [Contributing Guide](CONTRIBUTING.md) for details.

| Type | How |
|---|---|
| 🐛 Found a bug | [Open an Issue](../../issues/new?template=bug_report.md) |
| 💡 Feature idea | [Open an Issue](../../issues/new?template=feature_request.md) |
| 📝 Improve the game | Submit a Pull Request |

---

## 🔗 Links

- 🐦 X / Twitter: [@Devringdominion](https://x.com/Devringdominion)
- 💻 Repository: [github.com/blackBullAgents/Ring-dominions-](https://github.com/blackBullAgents/Ring-dominions-)

---

## 📄 License

Released under the [MIT License](LICENSE).

---

**⭐ If you enjoy Ring Dominion, consider starring the repo!**
