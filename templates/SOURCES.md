# Prompt catalog sources

The catalog contains original prompt adaptations of the sources below, consulted
on **September 7, 2026**. The three original templates (`general`, `code`, and
`review`) are simple project-authored briefs. The nine additions cover different
tasks and methods; their effectiveness depends on the model, input, and task.
They have been checked for catalog validity and rendering, not benchmarked for
model performance.

| Template ID | Primary source | Adaptation |
| --- | --- | --- |
| `co_star` | [GovTech Singapore: Mastering the art of prompt engineering with EMPOWER](https://www.tech.gov.sg/technews/mastering-the-art-of-prompt-engineering-with-empower/) | Uses the CO-STAR dimensions: context, objective, style, tone, audience, and response. The directions are original, not a copied example prompt. |
| `few_shot` | [Google: Prompt design strategies](https://ai.google.dev/gemini-api/docs/prompting-strategies) | Uses varied, consistently formatted input/output examples to specify a transformation. Example count and quality should be tested for the task. |
| `grounded_answer` | [Anthropic: Reduce hallucinations](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) | Asks for evidence from supplied documents, checkable references, and explicit uncertainty when support is missing. These directions do not guarantee factual accuracy. |
| `structured_extraction` | [Google: Structured outputs](https://ai.google.dev/gemini-api/docs/structured-output) | Applies explicit types, field descriptions, and semantic checks to an extraction brief. A text prompt alone does not enforce JSON or schema validity; strict output requires the consuming API's structured-output feature and application validation. |
| `decision_matrix` | [ASQ: Decision matrix](https://asq.org/quality-resources/decision-matrix) | Adapts the weighted comparison method, consistent score direction, and evidence-based criteria to a prompt. This is a decision-support technique, not a demonstrated LLM performance improvement. Verify weights, scores, and arithmetic. |
| `debug_diagnosis` | [Anthropic: Common workflows](https://code.claude.com/docs/en/common-workflows) | Extends the debugging guidance on error context, reproduction, and tests into a diagnostic brief. Checks and test outcomes must remain unverified unless actually executed. |
| `implementation_plan` | [Anthropic: Best practices](https://code.claude.com/docs/en/best-practices) | Adapts exploration before planning and concrete verification criteria. This template requests a plan; it does not implement changes or execute tests. |
| `critique_revision` | [Madaan et al.: Self-Refine (2023)](https://arxiv.org/abs/2303.17651) | Adapts feedback followed by refinement into one critique/revision pass over a supplied draft. It does not implement the paper's iterative pipeline or reproduce its reported results. |
| `research_brief` | [Shao et al.: STORM (2024)](https://arxiv.org/abs/2402.14207) | Takes inspiration from research across perspectives before outlining. It does not implement STORM's retrieval and dialogue system; browsing is conditional on tools available in the destination assistant. |

Each researched entry also records its source title and URL in `sources` within
[prompts.json](prompts.json). These are provenance metadata, not citations for a
user's eventual answer, and are excluded from the assembled prompt. The wizard
does not fetch sources, call a model, or run research tools.

To add or revise entries, follow the
[Structured Prompt Author skill](../skills/structured-prompt-author/SKILL.md),
update these notes when researching a bundled template, and run
`make validate-templates`.
