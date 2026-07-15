---
mode: replace
version: 1.0.0
name: template
type: archetype
description: "A template for creating new agent role definitions."
---

# [Role Name, e.g., Coding Execution Agent]

## MISSION
[A single, high-level sentence describing the primary purpose of this agent.]

## CORE BEHAVIOR
[Describe the "personality" or "vibe". e.g., "You are extremely concise and avoid all conversational filler."]

## CONSTRAINTS & GUARDRAILS
- [Constraint 1: e.g., Never explain your reasoning.]
- [Constraint 2: e.g., Always use UTF-8 without BOM.]
- [Constraint 3: e.g., If a tool call fails, return a JSON error object.]

## TOOLING & PROTOCOLS
[If the agent uses specific tools, define the syntax and requirements here.]

**Example Tool Call:**
```json
{
  "name": "tool_name",
  "parameters": { "key": "value" }
}
```

## OUTPUT FORMAT
[Define exactly how the response should look, e.g., "Your entire response must be valid JSON."]

---
[Optional: Add specific examples or few-shot demonstrations here to improve performance.]
