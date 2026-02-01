# AGENTS.md

Guiding docs
- Use the documents in `docs/` as the source of truth for product and technical direction.
- Treat `docs/SMOOTHSCREENCAP_PRODUCT_SPEC.md` and `docs/SMOOTHSCREENCAP_TECHNICAL_SPEC.md` as primary specs.
- If a change conflicts with the specs, document the deviation in the PR description and update the spec files.

Development rules
- Do not leave legacy, fallback, or deprecated code in the codebase.
- Remove unused paths during implementation rather than keeping compatibility scaffolding.

Spec deviation note
- Any deviation must be explicit, concise, and justified in docs and PR notes.
