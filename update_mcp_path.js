const fs = require('fs');
const path = require('path');
const file = path.join(process.env.HOME, '.claude', 'settings.json');

if (fs.existsSync(file)) {
  let data = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (data.mcpServers && data.mcpServers['fetch-local']) {
    data.mcpServers['fetch-local'].command = "/opt/homebrew/bin/npx";
    fs.writeFileSync(file, JSON.stringify(data, null, 2));
    console.log("Updated fetch-local command to absolute path.");
  }
}
