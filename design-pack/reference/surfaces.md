# The five irreversible surfaces

A question belongs to the owner if and only if its plausible answers change one
of these five surfaces. Everything else the agent decides itself, records as a
`D-NNN` with alternatives, and moves on. This is a filter applied before every
candidate question, not a guideline to weigh.

| Surface | Definition | What "changes it" looks like |
| --- | --- | --- |
| **data** | entities, relationships, identifiers, what is stored, for how long | a new entity or a merged one; a one-to-one becoming one-to-many; an identifier that is or is not stable or opaque; a retention period; what is deleted versus anonymized |
| **security** | who can access what, authentication model, tenancy boundary, trust boundaries | a role that exists or does not; two credential types or one; where the tenant boundary sits; what the server trusts from the client; what is logged |
| **scope** | what is MVP, what is Future, what is excluded | a capability moving between MVP, Future and Out of Scope; an integration that does or does not exist; a "simplified" version of a feature |
| **external** | money, third parties, jurisdiction, legal or regulatory obligations, retention mandated from outside | a paid provider; where data is hosted; a regulation that applies; a contract term; a third party that receives data |
| **ux** | primary navigation structure, critical user journeys, brand behaviour | the top-level navigation model; the shape of a critical journey (how a user gets in, completes the core task, gets out); what the brand promises visibly |

## Reference examples

Drawn from the exemplar project; use them as calibration, not as domain content.

- data: one profile per Stay, no cross-Stay profile. Answering the other way creates a persistent guest identity, a new entity with its own retention and consent story.
- security: guest credentials separate from Admin session cookies. Answering the other way means one credential type crosses a trust boundary.
- scope: no chat, no payments, no AI in MVP. Any of these is months of work and a different product.
- external: EU VPS, no public OpenStreetMap tiles in production, 365-day PII retention. Hosting location is jurisdiction; the tile server is a third party's terms of use; retention is a regulatory posture.
- ux: "Reception is an action, not a tab". The mockup showed a chat thread; the specs exclude chat; the navigation model changes depending on the answer.

## Never a card

These touch none of the five surfaces. Decide, record a `D-NNN` with the alternatives you rejected, and do not ask:

- test runner, formatter, linter, static-analysis level, type checker
- the language, framework and libraries when the inputs leave them open: a `D-NNN` with the
  alternatives weighed, never a card (the hosting provider, the region and anything paid are
  `external` and are cards; see trap 1)
- directory layout and naming inside the layout the requirements fix
- library choice within the fixed stack (an ORM plugin, a validation helper, a UI component library that does not change the navigation)
- local ports, container names, environment variable names
- CI platform when the remote is known; pipeline stage names; cache strategy
- the shape of the command contract (target names), as long as every gate the specs require has a target
- OpenAPI generator, client generator, migration tool, when the requirements fix "generated contract" but not the tool
- code style, commit message format, branch naming

Two traps:

1. **A tooling choice that leaks into a surface is a card.** "Which map library" is tooling; "which tile provider" is external (terms of use, cost). "Which email library" is tooling; "which email provider and who pays" is external. "Which auth library" is tooling; "sessions or tokens for staff" is security.
2. **A default that is reasonable is still a decision.** "Obviously the tenant boundary is the company" is a security decision. Reasonableness is not the test; surface is.

## The procedure

For every candidate decision found in the inputs or arising while writing:

1. Name the plausible answers (at least two; if only one is plausible it is not a decision, it is a fact from the input, tag it `[input]`).
2. For each answer, ask: does choosing it over the others change data, security, scope, external commitments or UX? Write the concrete consequence in one clause.
3. If at least one answer changes a surface: write a decision card (see `decision-card.md`). You may not decide it.
4. If no answer changes any surface: decide it now, record `D-NNN` with the rejected alternatives, tag the resulting statements `[D-NNN]`.
5. If you are unsure whether a surface is touched, it is touched. Write the card; the owner can accept the recommendation in one word.
