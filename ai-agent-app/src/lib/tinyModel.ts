import weights from '../weights.json';

type W = { vocab: string[]; labels: string[]; W: number[][]; b: number[] };

const M = weights as unknown as W;

export function classifyIntent(text: string): { label: string; confidence: number } {
  const vi: Record<string, number> = {};
  M.vocab.forEach((w, i) => { vi[w] = i; });
  const x = new Array(M.vocab.length).fill(0);
  for (const w of text.toLowerCase().split(/\s+/)) {
    if (vi[w] !== undefined) x[vi[w]] = 1;
  }
  const logits = M.labels.map((_, k) => M.W[k].reduce((s, w, j) => s + w * x[j], 0) + M.b[k]);
  const mx = Math.max(...logits);
  const exps = logits.map(l => Math.exp(l - mx));
  const s = exps.reduce((a, b) => a + b, 0);
  const probs = exps.map(e => e / s);
  let best = 0;
  probs.forEach((p, i) => { if (p > probs[best]) best = i; });
  return { label: M.labels[best], confidence: probs[best] };
}
