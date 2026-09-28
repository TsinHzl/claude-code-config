const fs = require('fs');
const file = '/Users/MacBook/.claude/CLAUDE.md';
let content = fs.readFileSync(file, 'utf8');

// Find the index of the header we added
const headerIndex = content.indexOf('## 网络搜索强制规则');

if (headerIndex !== -1) {
  content = content.substring(0, headerIndex).trimEnd() + '\n';
  fs.writeFileSync(file, content);
  console.log("Removed the override rules from CLAUDE.md");
} else {
  console.log("Rule not found.");
}
