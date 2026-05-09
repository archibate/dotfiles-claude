# frontend-design references

Curated library distilled from the open-design / awesome-design-md / huashu-design lineage. **Optional, lazy-loaded.** Default behavior of `frontend-design` is first-principles fresh design; consult these only when the user names a specific brand, aesthetic, or device.

## Layout

```
references/
├── styles/<slug>/             ~100 aesthetic recipes — each folder has SKILL.md
│                              (visual spec) + example.html (rendered reference)
│                              + sometimes references/{themes,layouts,components,
│                              checklist}.md and assets/template.html.
│                              Examples: html-ppt-taste-brutalist, html-ppt-hermes-
│                              cyber-terminal, web-prototype-taste-editorial,
│                              html-ppt-xhs-pastel-card, html-ppt-graphify-dark-
│                              graph, magazine-poster, dashboard, mobile-app, ...
├── design-systems/<brand>/    145 brand systems — each holds a 9-section DESIGN.md
│                              (color · typography · spacing · layout · components ·
│                              motion · voice · brand · anti-patterns).
│                              Examples: linear-app, stripe, vercel, claude
│                              (Anthropic), notion, apple, cursor, supabase,
│                              figma, tesla, spotify, airbnb, xiaohongshu, ...
└── frames/                    5 pixel-precise device chrome HTML — iphone-15-pro,
                               android-pixel, ipad-pro, macbook, browser-chrome
                               (+ this README). Inline-include when wrapping a
                               mobile/web mock.
```

## When to consult

Either:

- The user **explicitly names** something the library can match —
  - a brand (Linear, Stripe, Anthropic, Notion, Apple, Tesla, 小红书, …) → look in `design-systems/`;
  - an aesthetic keyword (tactical-telemetry, brutalist, editorial-minimalist, cyber-terminal, magazine, xhs/小红书 carousel, …) → look in `styles/`;
  - a device chrome (iPhone 15 Pro, Pixel, iPad Pro, MacBook, browser chrome) → look in `frames/`.
- Or the user **asks for more aesthetic choices** / "show me options" / "what styles are available" — surface a short curated shortlist (5-10 entries with one-line summary), let them pick, then `Read` the chosen one.

## When NOT to consult

- User gives a fresh aesthetic direction not in the library → design from scratch per `SKILL.md`.
- User says "surprise me" / "your taste" / "be creative" → pick freely; do not anchor on the library.
- Small components / utilities where pulling a full deck spec is overkill.
- Any prompt that doesn't name something matchable → first-principles wins.

## Discovery pattern

1. Parse the user's request for explicit names.
2. `ls references/styles/`, `ls references/design-systems/`, `ls references/frames/` — match by slug substring first (slugs are kebab-case folder names, e.g. `linear-app`, `html-ppt-taste-brutalist`).
3. **If no slug substring matches**, fall back to grepping the file text of `SKILL.md` (YAML frontmatter `description:` plus body) and `DESIGN.md` (markdown body — DESIGN.md has no frontmatter, so just rg the whole file). Many aesthetics live in descriptions, not slugs. Examples: "tactical-telemetry" → described inside `html-ppt-taste-brutalist/SKILL.md`; "editorial-minimalist" → inside `html-ppt-taste-editorial/SKILL.md`; "Anthropic" the brand → the slug is `claude`. Use `rg -li '<keyword>' references/{styles,design-systems}/*/SKILL.md references/design-systems/*/DESIGN.md`.
4. `Read` the matching `SKILL.md` / `DESIGN.md` first; only `Read` `example.html` / `template.html` if you need concrete CSS to mimic.
5. Treat references as **inspiration, not prescription** — fuse with the user's brief, don't rote-copy. The reference is the floor; the user's brief is the ceiling.
6. If nothing matches after both slug and description grep, fall back to first-principles design per `SKILL.md`. Do not force a near-miss reference.

## Anti-pattern

Reflexively `Read`-ing a reference on every task because the library exists. The library biases toward already-seen aesthetics; the skill's stated value is **avoiding generic AI-slop and varying across generations**. When in doubt, design fresh.
