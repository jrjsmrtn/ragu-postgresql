# 1. Record Architecture Decisions

Date: 2026-06-13

## Status

Accepted

## Context

Ragù PostgreSQL requires a systematic approach to documenting significant
architectural and technical decisions. As the project evolves, we need a clear
record of why decisions were made, what alternatives were considered, and what
trade-offs were accepted.

This is especially important for AI-assisted development, where decisions made
in one session need to be understood in future sessions.

## Decision

We will use Architecture Decision Records (ADRs) to document significant
architectural decisions.

**ADR Location**: All ADRs stored in `docs/adr/`.

**ADR Format**: Following the format established by Michael Nygard:

- **Title**: `# N. Title` (adrtools format, required for Structurizr `!adrs`)
- **Status**: Proposed, Accepted, Deprecated, Superseded
- **Context**: Forces at play (technical, business, social)
- **Decision**: The response to those forces
- **Consequences**: Resulting context after applying the decision

**Numbering**: Sequential four-digit format (0001, 0002, …) with no gaps.

**What Warrants an ADR**:

- Technology / extension choices
- Architectural patterns (e.g. single multi-extension instance vs. many services)
- Build and packaging approaches
- Security-related choices
- Decisions that would be costly to reverse

## Consequences

**Positive**:

- Clear record of why decisions were made
- Context preserved for future maintainers and AI assistants
- Reduced repeated discussion about settled decisions

**Negative**:

- Overhead of writing and maintaining ADRs
- Risk of ADRs becoming outdated if not maintained

## References

- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) — Michael Nygard
- [ADR GitHub Organization](https://adr.github.io/)
