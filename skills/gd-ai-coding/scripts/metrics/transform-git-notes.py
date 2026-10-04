#!/usr/bin/env python3
"""
Transform git notes from a local work-dir repo into dashboard-compatible JSON.

Usage: python3 transform-git-notes.py <work_dir>

Output:
  /tmp/dac-git-ai-notes.json    — { email: {ai_commits, ai_lines_added, ai_lines_accepted, models_used} }
  /tmp/dac-git-trace-notes.json — { email: [{req_name, phases, features, ...}] }
"""
import json, re, subprocess, sys

WORK_DIR    = sys.argv[1] if len(sys.argv) > 1 else '/tmp/dac-git-notes-work'
AI_OUTPUT    = '/tmp/dac-git-ai-notes.json'
TRACE_OUTPUT = '/tmp/dac-git-trace-notes.json'


def git(*args):
    return subprocess.run(['git'] + list(args), capture_output=True, text=True, cwd=WORK_DIR).stdout


def iter_notes(ref):
    listing = git('notes', '--ref', f'refs/notes/{ref}', 'list').strip()
    if not listing:
        return
    for line in listing.split('\n'):
        parts = line.split()
        if len(parts) != 2:
            continue
        note_obj, commit = parts
        raw = git('cat-file', '-p', note_obj).strip()
        body = raw.split('\n', 1)[1] if raw.startswith('---') else raw
        try:
            yield commit, json.loads(body)
        except json.JSONDecodeError:
            pass


def extract_email(author_str):
    if not author_str:
        return None
    m = re.search(r'<(.+?)>', str(author_str))
    return m.group(1) if m else str(author_str).strip()


# ── refs/notes/ai ────────────────────────────────────────────────────────────
print('[transform-git-notes] 处理 refs/notes/ai ...')
ai_stats = {}  # email -> stats dict

for commit, d in iter_notes('ai'):
    for p in d.get('prompts', {}).values():
        email = extract_email(p.get('human_author'))
        if not email:
            continue
        agent = p.get('agent_id') or {}
        model = agent.get('model', '') if isinstance(agent, dict) else ''
        additions = int(p.get('total_additions') or 0)
        accepted  = int(p.get('accepted_lines')  or 0)

        if email not in ai_stats:
            ai_stats[email] = {
                'ai_commits':       0,
                'ai_lines_added':   0,
                'ai_lines_accepted': 0,
                'models_used':      set(),
            }
        ai_stats[email]['ai_commits']        += 1
        ai_stats[email]['ai_lines_added']    += additions
        ai_stats[email]['ai_lines_accepted'] += accepted
        if model:
            ai_stats[email]['models_used'].add(model)

for v in ai_stats.values():
    v['models_used'] = sorted(v['models_used'])

with open(AI_OUTPUT, 'w', encoding='utf-8') as f:
    json.dump(ai_stats, f, ensure_ascii=False, indent=2)
print(f'[transform-git-notes] AI stats: {len(ai_stats)} 位成员 → {AI_OUTPUT}')


# ── refs/notes/dac-trace ────────────────────────────────────────────────────
print('[transform-git-notes] 处理 refs/notes/dac-trace ...')
trace_data = {}  # committer_email -> [req records]

for commit, d in iter_notes('dac-trace'):
    req_name  = d.get('req_name', '')
    committer = d.get('committer', '')
    if not req_name or not committer:
        continue
    entry = {
        'req_name':             req_name,
        'phases':               d.get('phases', []),
        'features':             d.get('features', []),
        'workflow_session_ids': d.get('workflow_session_ids', []),
        'last_commit':          commit,
    }
    # DDP 司机端版本名：git note 主体保留了该字段（setup-hook-wrapper.sh 增量合并完整
    # trace 内容），须透传给下游 merge_trace 的 _stamp_versions，否则"trace 自带版本名优先"
    # 分支在 git-notes 刷新链路上永不命中，版本会随 DDP 改派漂移。仅非空时带出。
    _rvn = d.get('release_version_name')
    if _rvn:
        entry['release_version_name'] = _rvn
    trace_data.setdefault(committer, []).append(entry)

with open(TRACE_OUTPUT, 'w', encoding='utf-8') as f:
    json.dump(trace_data, f, ensure_ascii=False, indent=2)
print(f'[transform-git-notes] trace data: {len(trace_data)} 位成员 → {TRACE_OUTPUT}')
