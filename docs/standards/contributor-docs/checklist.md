# Formatting Checklist

Quality rules for all contributor documentation files. These apply universally across all section types.

---

## Structure

- [ ] Use headers (H2, H3) to structure all content -- avoid long prose blocks without headers
- [ ] Every file starts with YAML frontmatter
- [ ] Every file has a 1-3 line summary immediately after frontmatter, before the first H2
- [ ] No file exceeds ~300 lines. If longer, split into multiple files
- [ ] Summary-first rule: an LLM reading frontmatter + first paragraph can decide whether to read the full file

## Code

- [ ] All code blocks specify a language (` ```typescript `, ` ```json `, never bare ` ``` `)
- [ ] Code snippets are short (<15 lines) and illustrate a key insight, not full implementations

## Format

- [ ] Use `.mdx` extension for all files
- [ ] Use Mermaid (` ```mermaid `) for all diagrams
- [ ] If the project has CodeHike configured, use CodeHike annotations for code walkthroughs
- [ ] Cross-references use relative MDX paths, not plain text names

## Completeness

- [ ] No orphan files -- every file is referenced from its `index.mdx` or a parent
- [ ] Every cross-reference in frontmatter (`concepts`, `algorithms`, `surfaces`, `related`) resolves to a real file
- [ ] Every inline link resolves to a real file
- [ ] Terminology is consistent -- the same thing is not called different names in different files

## Content Quality

- [ ] Features describe "what," not "why" -- defer "why" to concepts
- [ ] Concepts don't duplicate ADR content -- link to ADRs for decision context
- [ ] Algorithms emphasize "why this way" over "how it works" -- rejected alternatives and roadblocks are documented
- [ ] Surfaces document all error responses, not just the happy path
- [ ] No concept is explained inline in a feature -- if it needs >5 lines of explanation, extract it to a concept file
