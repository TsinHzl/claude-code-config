const fs = require('fs');
const path = require('path');
const file = path.join(process.env.HOME, '.claude', 'settings.json');

let data = {};
if (fs.existsSync(file)) {
  data = JSON.parse(fs.readFileSync(file, 'utf8'));
}

if (!data.mcpServers) {
  data.mcpServers = {};
}

data.mcpServers['fetch-local'] = {
  "type": "stdio",
  "command": "/opt/homebrew/bin/npx", // User is on mac, npx might be in homebrew or default path. Let's use generic npx
  "args": ["-y", "@modelcontextprotocol/server-fetch"]
};

// Also let's fix the command path to just "npx" if we are not sure, or use env resolution
data.mcpServers['fetch-local'].command = "npx";

fs.writeFileSync(file, JSON.stringify(data, null, 2));
console.log("Successfully added fetch-local to settings.json");
