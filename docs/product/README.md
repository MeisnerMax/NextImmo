# NexImmo Product Rebuild

This directory is the persistent source of truth for the planned NexImmo screen and product rebuild.

## Mandatory reading order for a new chat

1. `docs/product/PRODUCT_RESTORE_MASTER_PLAN.md`
2. `docs/product/PRODUCT_UX_FOUNDATION.md` — binding UX/system spine for every screen
3. `docs/product/SCREEN_SPEC_TEMPLATE.md`
4. `docs/product/CHAT_START_PROMPTS.md`
5. When available: `docs/product/PRODUCT_SCREEN_MAP.md`
6. When available: `docs/product/PRODUCT_RESTORE_TRACKER.md`
7. For a specific screen: `docs/product/screens/<screen>.md`

A new ChatGPT or Claude chat must assume it has **no prior conversational context**. It must read the relevant repo documents and current code before making product, architecture, or implementation decisions.

## Roles

- **Planning chat (ChatGPT or Claude):** product/UX planning, screen specification, dependency and backend-gap analysis. No implementation.
- **Claude Code implementation chat:** repo inspection, red-first tests where appropriate, implementation, validation, commit/push/PR. No product redesign beyond the approved specification.
- **Integration chat:** merge-order review, cross-screen consistency, CI, staging and wave-level E2E.

## Core rule

Do not rebuild rudimentary screens one-for-one. Each screen is planned properly first, documented as a specification, then implemented from that specification.

## Parallel work

Parallel Claude Code chats are allowed only through separate branches/worktrees and after shared UX/foundation contracts are stable. Screen agents must not independently redesign shared components, domain contracts, database schema, RLS, or permissions without a separately approved gap/package.
