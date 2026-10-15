import { useState, useRef, useEffect } from 'react';
import { initEngine, chat, isEngineReady } from './lib/ai';
import type { ChatMessage } from './lib/ai';

type Msg = { role: 'user' | 'assistant' | 'system'; content: string };

export default function App() {
  const [messages, setMessages] = useState<Msg[]>([]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState('Not loaded');
  const [progress, setProgress] = useState(0);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [messages]);

  async function loadModel() {
    setStatus('Loading model...');
    try {
      await initEngine((p) => { setStatus(p.text); setProgress(Math.round(p.progress * 100)); });
      setStatus('Ready');
      setProgress(100);
    } catch (e: any) {
      setStatus('Error: ' + (e?.message || e));
    }
  }

  async function send() {
    if (!input.trim() || loading) return;
    if (!isEngineReady()) { await loadModel(); }
    const userMsg: Msg = { role: 'user', content: input };
    const next = [...messages, userMsg];
    setMessages(next);
    setInput('');
    setLoading(true);
    try {
      const history: ChatMessage[] = next.map(m => ({ role: m.role as any, content: m.content }));
      let acc = '';
      const reply = await chat(history, (t) => {
        acc += t;
        setMessages(prev => {
          const last = prev[prev.length - 1];
          if (last && last.role === 'assistant' && last.content.startsWith('__stream__')) {
            return [...prev.slice(0, -1), { role: 'assistant', content: '__stream__' + acc }];
          }
          return [...prev, { role: 'assistant', content: '__stream__' + acc }];
        });
      });
      setMessages(prev => {
        // replace streaming placeholder with final
        const filtered = prev.filter(m => !(m.role === 'assistant' && m.content.startsWith('__stream__')));
        return [...filtered, { role: 'assistant', content: reply }];
      });
    } catch (e: any) {
      setMessages(prev => [...prev, { role: 'assistant', content: 'Error: ' + (e?.message || e) }]);
    } finally {
      setLoading(false);
    }
  }

  function renderContent(c: string) {
    if (c.startsWith('__stream__')) c = c.slice(10);
    return c;
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', background: '#0f172a', color: '#e2e8f0', fontFamily: 'system-ui' }}>
      <header style={{ padding: '12px 16px', borderBottom: '1px solid #1e293b', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1 style={{ margin: 0, fontSize: 18 }}>Nexus AI Agent</h1>
        <div style={{ fontSize: 12, color: '#94a3b8' }}>
          {status} {progress > 0 && progress < 100 ? `(${progress}%)` : ''}
        </div>
      </header>
      {!isEngineReady() && (
        <div style={{ padding: 16, textAlign: 'center' }}>
          <button onClick={loadModel} style={{ padding: '10px 20px', background: '#3b82f6', color: '#fff', border: 'none', borderRadius: 8, cursor: 'pointer' }}>
            Load Local Model (no API key)
          </button>
          <p style={{ fontSize: 12, color: '#94a3b8' }}>Model downloads once and runs in your browser/device.</p>
        </div>
      )}
      <div style={{ flex: 1, overflowY: 'auto', padding: 16 }}>
        {messages.map((m, i) => (
          <div key={i} style={{ marginBottom: 12, textAlign: m.role === 'user' ? 'right' : 'left' }}>
            <div style={{
              display: 'inline-block', maxWidth: '80%', padding: '8px 12px', borderRadius: 12,
              background: m.role === 'user' ? '#3b82f6' : '#1e293b', whiteSpace: 'pre-wrap'
            }}>
              {renderContent(m.content)}
            </div>
          </div>
        ))}
        <div ref={bottomRef} />
      </div>
      <div style={{ padding: 12, borderTop: '1px solid #1e293b', display: 'flex', gap: 8 }}>
        <input
          value={input}
          onChange={e => setInput(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && send()}
          placeholder="Ask anything..."
          style={{ flex: 1, padding: 10, borderRadius: 8, border: '1px solid #334155', background: '#1e293b', color: '#e2e8f0' }}
          disabled={loading}
        />
        <button onClick={send} disabled={loading} style={{ padding: '10px 16px', background: '#10b981', color: '#fff', border: 'none', borderRadius: 8, cursor: 'pointer' }}>
          {loading ? '...' : 'Send'}
        </button>
      </div>
    </div>
  );
}
