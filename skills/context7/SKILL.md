---
name: context7
description: >
  Fetch current documentation for libraries, frameworks, SDKs, APIs, and CLI tools via
  Context7. This skill should be used before calling any library API whose exact syntax,
  configuration, or version-specific behavior is uncertain — even well-known ones like
  React, Next.js, Prisma, Express, Tailwind, Django, or Spring Boot. Covers API syntax,
  configuration, version migration, and library-specific debugging. Prefer this over web
  search for library docs.
allowed-tools:
  - Bash(*mcpcall.py*:*)
---

# Context7

Fetch up-to-date library documentation and code examples. Requires `CONTEXT7_API_KEY` environment variable.

## resolve-library-id

Resolve a package/product name to a Context7 library ID. Call this before `query-docs` unless the user provides an ID in `/org/project` format.

- `libraryName` (required): Official library name (e.g., "Next.js", "Three.js")
- `query` (required): What the user needs help with — used to rank results by relevance

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py resolve-library-id libraryName:"Next.js" query:"app router setup"
```

## query-docs

Retrieve documentation and code examples for a resolved library.

- `libraryId` (required): Context7 library ID from `resolve-library-id` (e.g., "/vercel/next.js")
- `query` (required): Specific question — be detailed for better results

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py query-docs libraryId:"/vercel/next.js" query:"how to set up authentication with JWT"
```
