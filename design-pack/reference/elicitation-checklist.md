# Elicitation checklist

Run this sweep over the inputs in Stage A after extracting the candidate decisions
the inputs raise on their own. Its purpose is the opposite of the surface filter:
the filter keeps the skill from asking too much; this list keeps it from asking too
little. Every line is a question to ask of the inputs, not of the owner. When the
inputs answer it, tag the answer `[input]`. When they do not and the answer would
change the surface, write a card. When they do not and it would not, note a default.

This file is the one to amend when the downstream metric rises:
if implementation of a phase produced owner interventions on a surface, the
question that would have caught them belongs here.

## Data

- Which entities exist, and which of them the owner would recognise by name? Which are internal?
- For every relationship: one-to-one, one-to-many, or many-to-many? Optional or required?
- What identifies each entity to the outside world? Is that identifier stable, opaque, guessable?
- What is the lifecycle of each long-lived entity (states, who transitions them, what is final)?
- What is stored about people, and for how long? What happens at the end: delete, anonymize, keep aggregates?
- Is anything shared across organisational boundaries (accounts, tenants, workspaces)? Is anything explicitly not shared?
- What must be auditable, and what must the audit record never contain?
- What is imported from or exported to another system, in what shape?

## Security

- Who are the actors, including the ones without accounts (public visitor, email recipient, partner)?
- How does each actor authenticate? Are two actor classes ever allowed to share a credential type?
- Where is the ownership or tenancy boundary, and what derives it: the server, or something the client sends?
- Which actions need which permission? Are roles fixed or configurable?
- What does the server trust from the client, and what does it always recompute?
- What is secret (tokens, keys, links) and how is it stored, rotated, revoked?
- What may appear in logs, analytics and error messages, and what must never?
- Are there enumeration surfaces (guessable IDs, login errors that confirm existence)?

## Scope

- What does the input list as required? What does it list as later? What does it say is excluded?
- Which capabilities does the input describe with a "simplified", "basic" or "just" qualifier? What is the full version, and is the simplification a decision?
- Which integrations are assumed (payments, messaging, maps, email, identity providers, existing systems)? Which are named, which are implied?
- Which features would a reader expect from the product category that the input does not mention?
- Is there a feature whose absence would make the MVP unusable for its stated success criterion?
- What does "done" mean for the first release, in one sentence the owner would sign?

## External commitments

- Where is the system hosted, and does the jurisdiction matter to the owner or their customers?
- Which third parties receive data, and under what terms (providers, partners, analytics)?
- Which regulations or standards does the input name or imply (privacy law, accessibility law, sector rules)?
- What costs money per use or per month, and who pays? Is any provider fixed by contract?
- Are there retention or deletion mandates from outside the product?
- Are there licences or terms of use that constrain a component (map tiles, fonts, datasets)?
- Who owns the domain names, the certificates, the sending identities?

## Product identity and UX

- What is the top-level navigation model? Is it fixed by the product or configured by the customer?
- What are the critical journeys: how does each actor get in, do the core thing, and get out?
- What does the brand promise visibly (white-label, tone, a signature interaction)?
- Which languages, and what happens when a translation is missing?
- Which accessibility target, and is it a legal obligation or a design choice?
- Which device and context (mobile-first, desktop operations, kiosk, offline)?
- Is there a non-authoritative visual input, and where does it contradict the requirements?

## Always-present cards

Some cards recur on almost every project because inputs are almost always silent on them. Check them explicitly, and write the card when the input is silent:

- data: retention period for personal data, and the end-of-retention action
- security: whether the customer's own staff are one role or several
- scope: what is explicitly excluded from the first release (an empty exclusion list is a finding)
- external: hosting jurisdiction; who the transactional email provider is and who pays
- ux: the primary navigation model when the input describes screens but not how they connect
