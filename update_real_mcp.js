const fs = require('fs');
const file = '/Users/MacBook/.claude.json';

if (fs.existsSync(file)) {
  let data = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!data.mcpServers) {
    data.mcpServers = {};
  }
  data.mcpServers['fetch-local'] = {
    "type": "stdio",
    "command": "/opt/homebrew/bin/npx",
    "args": [
      "-y",
      "mcp-fetch-server"
    ],
    "env": {
      "npm_config_registry": "https://registry.npmjs.org/"
    }
  };
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
  console.log("Successfully added fetch-local with public registry fallback to .claude.json");
}
