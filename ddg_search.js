const q = process.argv.slice(2).join(' ');
fetch(`https://html.duckduckgo.com/html/?q=${encodeURIComponent(q)}`, {
  headers: { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }
})
.then(r => r.text())
.then(html => {
  const matches = [...html.matchAll(/<a class="result__url" href="([^"]+)">([^<]+)<\/a>/g)];
  if(matches.length === 0) console.log("No results or blocked.");
  console.log(matches.slice(0,5).map(m => m[2] + ' - ' + m[1]).join('\n'));
}).catch(console.error);
