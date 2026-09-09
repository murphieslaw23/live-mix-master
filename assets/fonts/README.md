# LiveMixMaster bundled fonts

LiveMixMaster uses three repository-approved UI families:

- **Roboto Condensed** — display/UI labels; variable `wght` font used at 600 and 700.
- **Inter** — body copy; variable `opsz,wght` font used at 400.
- **Roboto Mono** — numeric telemetry; variable `wght` font used at 600.

The binary TTF files are intentionally generated locally/CI instead of copied manually through the source-review tooling. Run:

```bash
bash tool/bootstrap_fonts.sh
```

The bootstrap is pinned to Google Fonts commit:

`0cf764bb712367b6079cbb4fd2353e6f54ec6850`

It verifies the downloaded bytes with Git blob SHAs before installing them:

| App asset | Google Fonts source | Git blob SHA |
| --- | --- | --- |
| `RobotoCondensed-Variable.ttf` | `ofl/robotocondensed/RobotoCondensed[wght].ttf` | `221055572bc92e324d26337dee7b43b435e39fc8` |
| `Inter-Variable.ttf` | `ofl/inter/Inter[opsz,wght].ttf` | `047c92f6e2212473dc436020afed689527076d44` |
| `RobotoMono-Variable.ttf` | `ofl/robotomono/RobotoMono[wght].ttf` | `f21d1d716bce3cc756bc618d32be71ce6f733f81` |

The exact upstream copyright notices and SIL Open Font License 1.1 are kept in `LICENSES.md`. CI must run the bootstrap before Flutter dependency resolution/build/test so production and golden output use the same verified font bytes.
