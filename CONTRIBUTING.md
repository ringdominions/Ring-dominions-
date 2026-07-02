# Contributing to Ring Dominion

First off, thanks for taking the time to contribute! 🎉

## How to Contribute

1. **Fork** the repository and create your branch from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
2. **Make your changes.** The whole game lives in [`index.html`](index.html) — HTML, CSS, and JS are kept together for a simple, dependency-free deploy.
3. **Test locally** by opening `index.html` in a browser (or serving it with `python3 -m http.server`).
4. **Commit your changes** using a clear message:
   ```bash
   git commit -m "feat: add new champion select animation"
   ```
5. **Push** to your fork and **open a Pull Request** against `main`.

## Reporting Bugs

Please use the [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.md) and include:
- Steps to reproduce
- Expected vs. actual behavior
- Browser/device info
- Screenshots or a screen recording, if possible

## Suggesting Features

Please use the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.md) and describe:
- The problem your feature solves
- Any alternatives you've considered

## Code Style

- Keep the game self-contained in `index.html` unless a change genuinely requires splitting files.
- Match the existing naming conventions and CSS variable usage (`--cyan`, `--mars`, `--ink`, etc.).
- Keep functions small and readable; add comments for non-obvious game-logic/math.

## Code of Conduct

By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

Thanks again for helping make Ring Dominion better! 🥊
