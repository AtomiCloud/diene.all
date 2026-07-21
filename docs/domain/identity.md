# Diene mobile identity

The template's default identity is a calm signal aperture: an editorial control
room with deep ink surfaces, teal signal paths, and orange attention markers.
It should be recognizable from the ring motif, typography, and asymmetric hero
composition before the name is read.

## Tokens

- Primary: landscape-specific teal, rose, amber, or deep teal from
  `config/<landscape>.yaml`.
- Secondary: a sharp counter-accent; never distribute both colors evenly.
- Display type: Newsreader. Body and control type: Atkinson Hyperlegible Next.
- Radius: 20 dp base with tighter control radii and a larger hero aperture.
- Motion: short signal-like fades; no decorative perpetual motion.

Canonical machine-readable values live in `assets/brand/tokens.json`. Runtime
colors come from the effective config tree, so a token change rebuilds the
theme without editing widgets.

## Assets and usage

`assets/brand/logo.svg` is the real colored logo. Each landscape has its own
SVG source, 1024 px raster source, Android density set, and iOS AppIcon catalog.
Do not recolor, stretch, replace with text, or substitute an emoji. Preserve
clear space around the mark and use the configured asset path.

The identity appears in the header, app icons, theme, loading/failure language,
empty state, and store-facing flavor names. New products must replace these
tokens and assets during scaffolding; default-grey shipping is forbidden.
