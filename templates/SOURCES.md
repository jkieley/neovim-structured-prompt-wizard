# Prompt catalog sources

The catalog contains 18 templates. The three original templates (`general`,
`code`, and `review`) are simple project-authored briefs. The other entries are
original adaptations of documented methods, not vendor-authored or endorsed
prompts. Their effectiveness depends on the model, input, and task. They have
been checked for catalog validity and rendering, not benchmarked for model
performance.

## Initial research — September 7, 2026

These nine additions retain their original IDs, fields, and order.

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

## Anthropic and OpenAI additions — September 9, 2026

The supporting sections below were opened and read on this date. The six entries
are appended to the existing catalog. Required task-specific inputs start blank;
defaults describe output preferences rather than supplying example facts.

| Template ID | Primary source | Adaptation |
| --- | --- | --- |
| `document_synthesis` | [Anthropic: Prompting best practices — Long context prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#long-context-prompting) | Places labeled documents before the purpose field and requests brief relevant excerpts before a synthesis of findings, disagreements, and gaps. This complements question answering with a cross-document brief. |
| `ticket_triage` | [Anthropic: Ticket routing](https://platform.claude.com/docs/en/about-claude/use-case-guides/ticket-routing) | Uses explicit intent categories, definitions, examples, and rules for ambiguous or competing requests. Produces classification recommendations with evidence; missing information leaves the category unset. |
| `support_reply` | [Anthropic: Customer support agent](https://platform.claude.com/docs/en/about-claude/use-case-guides/customer-support-chat) | Applies the guide's context, product scope, clarification, tone, and commitment boundaries to a reply draft using supplied policies and verified case facts, with separate reviewer notes. |
| `assistant_instructions` | [OpenAI: Prompt engineering — Message formatting with Markdown and XML](https://developers.openai.com/api/docs/guides/prompt-engineering#message-formatting-with-markdown-and-xml) | Drafts a reusable assistant prompt with separate Identity, Instructions, Examples, and Context sections. Its deliverable is the prompt itself, distinct from completing a general task. |
| `frontend_build` | [OpenAI: Prompt engineering — Front-end engineering](https://developers.openai.com/api/docs/guides/prompt-engineering#front-end-engineering) | Turns guidance on design consistency, reusable components, architecture, interaction states, and accessibility into an implementation brief with acceptance checks. Frameworks and dependencies remain project choices. |
| `compare_responses` | [OpenAI: Evaluation best practices — LLM-as-a-judge and model graders](https://developers.openai.com/api/docs/guides/evaluation-best-practices#llm-as-a-judge-and-model-graders) | Uses separate A/B response fields, an explicit rubric, optional reference evidence, and a verdict with concise justification. Allows ties or insufficient evidence and calls attention to order and verbosity bias. |

These are text prompts for the destination assistant. In particular:

- Document synthesis puts documents first among the fields. The wizard still
  prepends reusable instructions and renders Markdown sections; it does not
  generate Anthropic's example XML layout or promise a long-context speed or
  accuracy improvement. Source excerpts remain data, and citations need checking.
- Ticket triage does not route tickets or enforce categories through an API
  schema. Support replies are drafts: no records are fetched and no messages or
  account actions are performed by the wizard.
- Assistant instruction headings do not establish system/developer message roles.
  The consuming application chooses the appropriate instruction surface and
  supplies any tools. A list of capabilities does not provision them.
- Frontend implementation and verification depend on tools provided by the host.
  The prompt requests code and a checklist when those tools are unavailable.
- A comparison prompt cannot eliminate model-judge bias or establish objective
  quality on its own. Check judgments against human labels and consider swapping
  A/B order in separate runs. The wizard does not run an evaluation pipeline.
  These adaptations request concise evidence and conclusions, not hidden reasoning.

## Provenance and maintenance

Each researched entry also records its source title and URL in `sources` within
[prompts.json](prompts.json). These are provenance metadata, not citations for a
user's eventual answer, and are excluded from the assembled prompt. The wizard
does not fetch sources, call a model, or run research tools.

To add or revise entries, follow the
[Structured Prompt Author skill](../skills/structured-prompt-author/SKILL.md),
update these notes when researching a bundled template, and run
`make validate-templates`.
