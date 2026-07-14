const escape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// ponytail: enough of a JSON highlighter for the config samples in docs.json —
// keys, strings, punctuation. Reach for a real tokenizer only if the samples grow numbers or booleans.
export function highlightJson(source) {
  return escape(source).replace(
    /("(?:[^"\\]|\\.)*")(?=\s*:)|("(?:[^"\\]|\\.)*")|([{}[\],:])/g,
    (_, key, str, pun) => {
      if (key) return `<span class="tk-key">${key}</span>`;
      if (str) return `<span class="tk-str">${str}</span>`;
      return `<span class="tk-pun">${pun}</span>`;
    }
  );
}
