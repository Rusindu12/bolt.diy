import * as webllm from '@mlc-ai/web-llm';
import { classifyIntent } from './tinyModel';

export const MODEL_ID = 'Llama-3.2-1B-Instruct-q4f16_1-MLC';

export type ChatMessage = { role: 'system' | 'user' | 'assistant' | 'tool'; content: string };

export interface ProgressInfo { text: string; progress: number }

let engine: webllm.MLCEngine | null = null;
let enginePromise: Promise<webllm.MLCEngine> | null = null;

export async function initEngine(onProgress?: (p: ProgressInfo) => void): Promise<webllm.MLCEngine> {
  if (engine) return engine;
  if (enginePromise) return enginePromise;
  enginePromise = (async () => {
    const e = await webllm.CreateMLCEngine(MODEL_ID, {
      initProgressCallback: (report) => {
        onProgress?.({ text: report.text, progress: report.progress });
      },
    });
    engine = e;
    return e;
  })();
  return enginePromise;
}

export function isEngineReady() { return !!engine; }

// ---- Tools ----
export type ToolResult = { name: string; result: string };

const memory: Record<string, string> = {};

export const TOOLS_DESC = `
You are Nexus, a helpful local AI agent running entirely on the user's device (no API keys, no cloud).
You can use tools by replying with a single JSON object on its own line in this exact format:
{"tool": "<name>", "args": { ... }}

Available tools:
- calculator: args { "expr": "math expression" } -> evaluates safely.
- current_time: args {} -> returns current date/time.
- remember: args { "key": "...", "value": "..." } -> stores a note.
- recall: args { "key": "..." } -> retrieves a stored note (or all if key="*").
- fetch_url: args { "url": "https://..." } -> fetches text content of a URL.

When you need a tool, output ONLY the JSON tool call (no extra text). After you receive a tool result, continue reasoning and answer the user. When no tool is needed, answer normally.
`;

function safeEval(expr: string): string {
  // very restricted eval: only digits, operators, parens, spaces, dot
  if (!/^[0-9+\-*/().\s]+$/.test(expr)) return 'Error: invalid expression';
  try {
    // eslint-disable-next-line no-new-func
    const fn = new Function('return ' + expr);
    const v = fn();
    return String(v);
  } catch (e: any) {
    return 'Error: ' + (e?.message || e);
  }
}

export async function runTool(name: string, args: any): Promise<string> {
  switch (name) {
    case 'calculator':
      return safeEval(String(args?.expr ?? ''));
    case 'current_time':
      return new Date().toISOString();
    case 'remember':
      memory[String(args?.key)] = String(args?.value);
      return 'Stored.';
    case 'recall':
      if (args?.key === '*') return JSON.stringify(memory);
      return memory[String(args?.key)] ?? '(not found)';
    case 'fetch_url': {
      try {
        const r = await fetch(String(args?.url));
        const t = await r.text();
        return t.slice(0, 4000);
      } catch (e: any) {
        return 'Fetch error: ' + (e?.message || e);
      }
    }
    default:
      return 'Unknown tool: ' + name;
  }
}

export function parseToolCall(text: string): { name: string; args: any } | null {
  // find a JSON object with "tool"
  const m = text.match(/\{[\s\S]*"tool"[\s\S]*\}/);
  if (!m) return null;
  try {
    const obj = JSON.parse(m[0]);
    if (obj && typeof obj.tool === 'string') return { name: obj.tool, args: obj.args || {} };
  } catch {}
  return null;
}

export async function chat(messages: ChatMessage[], onToken?: (t: string) => void): Promise<string> {
  const e = await initEngine();
  const lastUser = [...messages].reverse().find(m => m.role === 'user')?.content || '';
  const intent = classifyIntent(lastUser);
  const fullMessages = [{ role: 'system' as const, content: TOOLS_DESC + `\n[Custom model intent: ${intent.label} (conf ${intent.confidence.toFixed(2)})]` }, ...messages];
  let accumulated = '';
  // agent loop (max 6 steps)
  for (let step = 0; step < 6; step++) {
    const res = await e.chat.completions.create({
      messages: fullMessages as any,
      temperature: 0.7,
      max_tokens: 512,
    });
    const content = res.choices?.[0]?.message?.content ?? '';
    const tool = parseToolCall(content);
    if (tool) {
      fullMessages.push({ role: 'assistant', content });
      const result = await runTool(tool.name, tool.args);
      fullMessages.push({ role: 'tool', content: `Tool ${tool.name} result: ${result}` });
      onToken?.(`🔧 ${tool.name}(${JSON.stringify(tool.args)}) → ${result}\n`);
      continue;
    }
    accumulated = content;
    onToken?.(content);
    fullMessages.push({ role: 'assistant', content });
    return content;
  }
  return accumulated || 'Agent reached max steps.';
}
