#!/usr/bin/env node
const { Server } = require('@modelcontextprotocol/sdk/server/index.js');
const { StdioServerTransport } = require('@modelcontextprotocol/sdk/server/stdio.js');
const { CallToolRequestSchema, ListToolsRequestSchema } = require('@modelcontextprotocol/sdk/types.js');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const server = new Server(
  { name: 'code-review', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

function run(cmd, cwd) {
  try {
    return {
      ok: true,
      output: execSync(cmd, {
        cwd: cwd || process.cwd(),
        encoding: 'utf8',
        maxBuffer: 50 * 1024 * 1024,
        timeout: 30000,
      }),
    };
  } catch (e) {
    return { ok: false, output: e.stderr || e.message || String(e) };
  }
}

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'git_current_branch',
      description: '获取当前 Git 分支名',
      inputSchema: {
        type: 'object',
        properties: { cwd: { type: 'string', description: '工作目录路径' } },
        required: ['cwd'],
      },
    },
    {
      name: 'git_origin_branch',
      description: '通过 reflog 找到当前分支的源头分支',
      inputSchema: {
        type: 'object',
        properties: {
          cwd: { type: 'string' },
          current_branch: { type: 'string' },
        },
        required: ['cwd', 'current_branch'],
      },
    },
    {
      name: 'git_diff',
      description: '获取两个分支之间的完整 diff（git diff origin_branch HEAD）',
      inputSchema: {
        type: 'object',
        properties: {
          cwd: { type: 'string' },
          origin_branch: { type: 'string' },
        },
        required: ['cwd', 'origin_branch'],
      },
    },
    {
      name: 'resolve_component_path',
      description: '将 @组件名/ 参数解析为真实目录路径',
      inputSchema: {
        type: 'object',
        properties: {
          base_dir: { type: 'string', description: '搜索起始目录' },
          component: { type: 'string', description: '组件名（可含 @/ 前缀）' },
        },
        required: ['base_dir', 'component'],
      },
    },
    {
      name: 'write_report',
      description: '将 Code Review 报告写入目标目录下的 md 文件',
      inputSchema: {
        type: 'object',
        properties: {
          dir: { type: 'string', description: '报告写入目录（通常是 git 根目录）' },
          filename: { type: 'string', description: '报告文件名，如 code-review-report.md' },
          content: { type: 'string', description: '报告 Markdown 内容' },
        },
        required: ['dir', 'filename', 'content'],
      },
    },
    {
      name: 'git_root',
      description: '获取当前工作目录所在的 git 仓库根目录',
      inputSchema: {
        type: 'object',
        properties: { cwd: { type: 'string' } },
        required: ['cwd'],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;

  if (name === 'git_current_branch') {
    const r = run('git branch --show-current', args.cwd);
    return { content: [{ type: 'text', text: r.ok ? r.output.trim() : `ERROR: ${r.output}` }] };
  }

  if (name === 'git_root') {
    const r = run('git rev-parse --show-toplevel', args.cwd);
    return { content: [{ type: 'text', text: r.ok ? r.output.trim() : `ERROR: ${r.output}` }] };
  }

  if (name === 'git_origin_branch') {
    const r = run(`git reflog show ${args.current_branch}`, args.cwd);
    if (!r.ok) return { content: [{ type: 'text', text: `ERROR: ${r.output}` }] };

    const lines = r.output.split('\n').filter(Boolean);
    let originBranch = null;

    // Look for "branch: Created from <branch>" pattern
    for (const line of lines) {
      const m = line.match(/branch: Created from (.+)$/);
      if (m) {
        originBranch = m[1].trim();
        break;
      }
    }

    // Fallback: look for checkout pattern
    if (!originBranch) {
      for (const line of lines) {
        const m = line.match(/checkout: moving from (.+) to /);
        if (m) {
          originBranch = m[1].trim();
          break;
        }
      }
    }

    // Last fallback: check common base branches
    if (!originBranch) {
      for (const candidate of ['main', 'master', 'develop', 'dev']) {
        const check = run(`git merge-base --is-ancestor ${candidate} ${args.current_branch}`, args.cwd);
        if (check.ok) {
          originBranch = candidate;
          break;
        }
      }
    }

    const result = originBranch || args.current_branch;
    return { content: [{ type: 'text', text: result }] };
  }

  if (name === 'git_diff') {
    const r = run(`git diff ${args.origin_branch} HEAD`, args.cwd);
    if (!r.ok) return { content: [{ type: 'text', text: `ERROR: ${r.output}` }] };

    const diff = r.output;
    // If diff is very large, write to temp file and read back
    if (diff.length > 5 * 1024 * 1024) {
      const tmp = path.join(os.tmpdir(), `cr-diff-${Date.now()}.txt`);
      fs.writeFileSync(tmp, diff, 'utf8');
      const content = fs.readFileSync(tmp, 'utf8');
      fs.unlinkSync(tmp);
      return { content: [{ type: 'text', text: content }] };
    }
    return { content: [{ type: 'text', text: diff }] };
  }

  if (name === 'resolve_component_path') {
    let component = args.component.replace(/^@/, '').replace(/\/$/, '');
    const baseDir = args.base_dir;

    // Try direct path first
    const direct = path.join(baseDir, component);
    if (fs.existsSync(direct)) {
      return { content: [{ type: 'text', text: direct }] };
    }

    // Search recursively up to 4 levels deep
    function findDir(searchBase, name, depth) {
      if (depth > 4) return null;
      try {
        const entries = fs.readdirSync(searchBase, { withFileTypes: true });
        for (const entry of entries) {
          if (!entry.isDirectory()) continue;
          if (entry.name === name) return path.join(searchBase, entry.name);
          const found = findDir(path.join(searchBase, entry.name), name, depth + 1);
          if (found) return found;
        }
      } catch (_) {}
      return null;
    }

    const found = findDir(baseDir, component, 0);
    return { content: [{ type: 'text', text: found || baseDir }] };
  }

  if (name === 'write_report') {
    try {
      const filePath = path.join(args.dir, args.filename);
      fs.writeFileSync(filePath, args.content, 'utf8');
      return { content: [{ type: 'text', text: `OK: ${filePath}` }] };
    } catch (e) {
      return { content: [{ type: 'text', text: `ERROR: ${e.message}` }] };
    }
  }

  return { content: [{ type: 'text', text: `ERROR: unknown tool ${name}` }] };
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((e) => {
  process.stderr.write(String(e) + '\n');
  process.exit(1);
});
