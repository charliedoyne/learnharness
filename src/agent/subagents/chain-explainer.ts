/**
 * The chain explainer (fork, 2026-11-07): fills in the one-line `why` of
 * chains written before the extractor gave reasons (contracts GraphChain.why).
 * A single-submit worker over a batch of chains; the cheap slot.
 */

import { Type, type Static } from "typebox";
import type { GraphChain, GraphNode } from "../../core/contracts.ts";
import type { PiEngine } from "../models.ts";
import { runSubmitAgent } from "./submit-agent.ts";

export const EXPLAINER_BATCH = 20;

export const EXPLAINER_INSTRUCTIONS = `Each chain below is premises that jointly entail a conclusion, in a learner's knowledge graph.
For every chain, write one plain sentence (at most 25 words) saying HOW the premises together give
the conclusion: the link a reader needs to see why it follows. Do not restate the premises in full;
name the step. Submit every chain's sentence in one submit_explanations call, keyed by the chain id.`;

const submitSchema = Type.Object({
	explanations: Type.Array(Type.Object({
		id: Type.String({ description: 'The chain id from the prompt, verbatim ("arg_…").' }),
		why: Type.String({ description: "One sentence, at most 25 words." }),
	})),
});

type ExplainSubmit = Static<typeof submitSchema>;

export function explainerPrompt(chains: ReadonlyArray<GraphChain>, byId: ReadonlyMap<string, GraphNode>): string {
	const idea = (id: string) => {
		const n = byId.get(id);
		return n ? `${n.name}: ${n.statement}` : id;
	};
	return `CHAINS\n\n${chains.map((c) => `[${c.id}]\n${c.premises.map((p) => `  premise  ${idea(p)}`).join("\n")}\n  ⟹        ${idea(c.conclusion)}`).join("\n\n")}`;
}

export async function explainChains(opts: {
	engine: PiEngine | undefined;
	chains: ReadonlyArray<GraphChain>;
	byId: ReadonlyMap<string, GraphNode>;
	signal?: AbortSignal;
}): Promise<Map<string, string>> {
	const ids = new Set(opts.chains.map((c) => c.id));
	const submitted = await runSubmitAgent<ExplainSubmit>({
		role: "explainer",
		toolName: "submit_explanations",
		toolDescription: "Submit one sentence per chain.",
		parameters: submitSchema,
		fill: (input: Partial<ExplainSubmit>) => ({ explanations: input.explanations ?? [] }),
		validate: (value) => {
			const seen = new Set(value.explanations.map((e) => e.id));
			const unknown = value.explanations.find((e) => !ids.has(e.id));
			if (unknown) return `unknown chain id "${unknown.id}" — use the ids from the prompt verbatim`;
			const missing = [...ids].filter((id) => !seen.has(id));
			return missing.length > 0 ? `missing explanations for: ${missing.join(", ")}` : null;
		},
		systemPrompt: EXPLAINER_INSTRUCTIONS,
		prompt: explainerPrompt(opts.chains, opts.byId),
		engine: opts.engine,
		signal: opts.signal,
		onStep: () => {},
		neverSubmitted: "the chain explainer never submitted",
	});
	return new Map(submitted.explanations.filter((e) => e.why.trim() !== "").map((e) => [e.id, e.why.trim()]));
}
