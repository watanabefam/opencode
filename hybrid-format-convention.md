# Hybrid Format Convention

## Rule
<RULE>
  Pair every Markdown heading with a matching XML tag at each major section boundary:

  ```
  ## SECTION NAME
  <SECTION_NAME>
    content...
  </SECTION_NAME>
  ```

  - Use `##` or `###` for human-readable labels
  - Use `<SECTION_NAME>` for machine-parseable boundaries
  - Apply at top-level sections only; keep deep nesting XML-only
</RULE>

## Why
<WHY>
  Different models parse prompts differently. Using both formats simultaneously works optimally across all major models without harming any one.
</WHY>

## Reference: Model Compatibility
<REFERENCE_MODEL_COMPATIBILITY>
  | Model | Input preference | Notes |
  |---|---|---|
  | Claude | XML tags | +40% quality on complex prompts with XML |
  | GPT | Markdown headers | "XML tags ignored" failure mode without headers |
  | Gemini | Either | Neutral |
  | DeepSeek | XML boundaries | Neutral |
  | Qwen | XML format | Neutral |
  | Grok | Format-agnostic | Neutral |
  | Llama | Markdown + XML mix | Neutral |
  | Mistral | Markdown | Smalls hit with pure XML |
</REFERENCE_MODEL_COMPATIBILITY>

## Reference: Output Format by Model
<REFERENCE_OUTPUT_FORMAT>
  | Model | Structured output | How |
  |---|---|---|
  | Claude | JSON or Markdown | Prompt-level instruction |
  | GPT | JSON (strict schema) | `response_format: {type: "json_schema"}` |
  | DeepSeek | JSON | `response_format: {type: "json_object"}` |
  | Gemini | JSON with schema | `response_format:` with JSON Schema |
  | Grok | JSON with schema | `response_format:` with `json_schema` |
  | Qwen | XML | Native |
  | Llama | JSON | Structured output API |
  | Mistral | JSON | `response_format: {type: "json_object"}` |

  Default to JSON for widest native support. Add "Return only JSON, no preamble, no markdown fences" as a prompt-level instruction.
</REFERENCE_OUTPUT_FORMAT>

## Token Cost
<TOKEN_COST>
  Hybrid format adds ~15-20% input tokens. For single-use prompts this is negligible. For high-volume pipelines, consider Markdown-only.
</TOKEN_COST>

> **Setup note**: List this file in `opencode.json`'s `instructions` array (`"instructions": ["hybrid-format-convention.md"]`) to load it as system context for any agent authoring or modifying prompt systems.
