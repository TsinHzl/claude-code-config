---
name: driver-mas-dev-update
description: 根据 MAS 任务 ID 查询关联开发分支，自动同步本地仓库并更新工程配置（pubspec.yaml / Podfile）。适用于输入 MAS 任务号、查询分支、更新开发环境、同步仓库等场景。
allowed-tools: ["Bash", "Read", "Edit", "AskUserQuestion"]
argument-hint: <MAS任务ID，如 MAS-1-132303 或 132303>
---

你是本地开发环境管理助手。用户提供 MAS 任务 ID 后，按以下步骤执行并在每步结尾输出耗时（秒）。

## 第一步：预检 & 收集参数（合并执行，1 次 Bash）

用单条 Bash 命令完成以下所有操作并输出 JSON：

```bash
python3 - << 'EOF'
import os, sys, time
t0 = time.time()

cookie = open(os.path.expanduser('~/.claude/mas-cookie.txt')).read().strip()
token  = open(os.path.expanduser('~/.claude/mas-token.txt')).read().strip()

# 任务 ID 标准化
task_id = "TASK_ID_PLACEHOLDER"  # 替换为用户输入，若无 MAS-1- 前缀则补全
if not task_id.startswith('MAS-'):
    task_id = f'MAS-1-{task_id}'

import json
print(json.dumps({"ok": True, "task_id": task_id, "elapsed": round(time.time()-t0,2)}))
EOF
```

若任意配置文件不存在，停止执行并提示：
```
⚠️  缺少配置文件。请从浏览器 Network 面板复制 batch-git-group 的 cURL，提取：
  echo 'COOKIE_VALUE'   > ~/.claude/mas-cookie.txt
  echo 'X_MAS_TOKEN'    > ~/.claude/mas-token.txt
  echo '{"X-Mas-Timestamp":"XXXXXX","X-Timestamp":"XXXXXX"}' > ~/.claude/mas-timestamps.json

注意：Token 和时间戳绑定生成，均有时效性，过期后需重新从浏览器获取。
```

同时，**立即询问用户工程路径**（不等后续步骤），以减少等待：
```
请输入本地工程根目录路径（Flutter 各仓库所在的父目录）：
```

## 第二步：API 查询 + 解析 + 展示（合并执行，1 次 Bash）

用单条 Bash 命令完成 curl 调用、JSON 解析、分类展示，并将结果写入 `/tmp/mas_branches.json`：

```bash
python3 - << 'EOF'
import subprocess, json, time, sys, re, os

t0 = time.time()
TASK_ID = "MAS-1-XXXXXX"  # 替换为实际值
PROJECT_ROOT = "/path/to/project"  # 替换为用户输入

cookie = open(os.path.expanduser('~/.claude/mas-cookie.txt')).read().strip()
token  = open(os.path.expanduser('~/.claude/mas-token.txt')).read().strip()

import time as _time, json as _json
# X-Mas-Token 与时间戳绑定，必须使用保存的原始时间戳
_ts_file = os.path.expanduser('~/.claude/mas-timestamps.json')
try:
    _ts = _json.load(open(_ts_file))
    ts_mas, ts_x = _ts['X-Mas-Timestamp'], _ts['X-Timestamp']
except FileNotFoundError:
    ts_mas = ts_x = str(int(_time.time() * 1000))

url = f"https://mas.intra.xiaojukeji.com/mas-workflow/workflow/requirement/{TASK_ID}/batch-git-group?branchMergeTypes=2,4,11"

cmd = [
    'curl', '-s', url,
    '-H', 'Accept: application/json, text/plain, */*',
    '-b', cookie,
    '-H', f'M-Timestamp: {token}',
    '-H', f'X-Mas-Token: {token}',
    '-H', f'X-Mas-Timestamp: {ts_mas}',
    '-H', f'X-Timestamp: {ts_x}',
    '-H', f'Referer: https://mas.intra.xiaojukeji.com/workflow/detail/19/ios?requirementId={TASK_ID}',
    '-H', 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
    '-H', 'X-Requested-With: XMLHttpRequest',
    '-H', 'Sec-Fetch-Mode: cors',
    '-H', 'Sec-Fetch-Site: same-origin',
]
resp = json.loads(subprocess.check_output(cmd))

if resp.get('code') != 0:
    print(f"❌ API 错误: {resp.get('message')} — 请更新 Cookie/Token")
    sys.exit(1)

flutter, native, seen = [], [], set()
for group in resp.get('data', []):
    if group.get('branchMergeType') != 2:
        continue
    for gg in group.get('gitGroups', []):
        for m in gg.get('projectModules', []):
            url_ = m.get('gitUrl', '')
            branch = m.get('relateBranch', '')
            if not branch or (url_, branch) in seen:
                continue
            seen.add((url_, branch))
            repo = url_.split('/')[-1].replace('.git', '')
            entry = {'repo': repo, 'git_url': url_, 'branch': branch}
            if m.get('componentType') in (3, 4):
                flutter.append(entry)
            else:
                native.append(entry)

with open('/tmp/mas_branches.json', 'w') as f:
    json.dump({'task_id': TASK_ID, 'project_root': PROJECT_ROOT, 'flutter': flutter, 'native': native}, f)

elapsed = round(time.time() - t0, 2)
total = len(flutter) + len(native)
print(f"✅ {TASK_ID} 共 {total} 个开发分支 | ⏱ 查询+解析: {elapsed}s\n")
print(f"### Flutter 组件（{len(flutter)} 个）")
print("| # | 仓库 | 分支 |")
print("|---|------|------|")
for i,b in enumerate(flutter,1): print(f"| {i} | `{b['repo']}` | `{b['branch']}` |")
print(f"\n### Native 组件（{len(native)} 个）")
print("| # | 仓库 | 分支 |")
print("|---|------|------|")
for i,b in enumerate(native,1): print(f"| {i} | `{b['repo']}` | `{b['branch']}` |")
EOF
```

## 第三步：同步仓库 + 更新配置（合并执行，1 次 Bash）

用单条 Bash 命令完成全部 git 操作和文件修改，**Flutter 仓库并行处理**：

```bash
python3 - << 'EOF'
import json, os, re, subprocess, time
from concurrent.futures import ThreadPoolExecutor, as_completed

t_total = time.time()
data = json.load(open('/tmp/mas_branches.json'))
PROJECT_ROOT = data['project_root']
TASK_ID = data['task_id']
flutter_repos = data['flutter']
native_repos  = data['native']

# ── 构建本次需求的 pkg/repo 映射 ──────────────────────────────
mas_flutter = {}  # pkg_name -> repo_name
for b in flutter_repos:
    repo = b['repo']
    if repo == 'driver_business':
        continue
    pkg = repo
    try:
        for line in open(f"{PROJECT_ROOT}/{repo}/pubspec.yaml"):
            if line.startswith('name:'):
                pkg = line.split(':',1)[1].strip(); break
    except FileNotFoundError:
        pass
    mas_flutter[pkg] = repo
mas_native = {b['repo'] for b in native_repos}

report_flutter, report_native = [], []

# ── Git 操作 ─────────────────────────────────────────────────
def sync_repo(repo_path, git_url, branch, label):
    t = time.time()
    if os.path.isdir(f"{repo_path}/.git"):
        r = subprocess.run(['git','-C',repo_path,'pull','origin',branch],
                           capture_output=True, text=True)
        status = '✅ pull' if r.returncode == 0 else f'⚠️  pull 失败'
    else:
        parent = os.path.dirname(repo_path)
        r = subprocess.run(['git','-C',parent,'clone',git_url], capture_output=True, text=True)
        if r.returncode == 0:
            subprocess.run(['git','-C',repo_path,'checkout',branch], capture_output=True)
        status = '🆕 clone' if r.returncode == 0 else '❌ clone 失败'
    return label, status, round(time.time()-t, 1)

# Flutter 并行
t_flutter = time.time()
with ThreadPoolExecutor(max_workers=6) as ex:
    futures = {}
    for b in flutter_repos:
        path = f"{PROJECT_ROOT}/{b['repo']}"
        f = ex.submit(sync_repo, path, b['git_url'], b['branch'], b['repo'])
        futures[f] = b
    for f in as_completed(futures):
        label, status, elapsed = f.result()
        report_flutter.append((label, futures[f]['branch'], status, elapsed))
print(f"⏱ Flutter 仓库同步: {round(time.time()-t_flutter,1)}s")

# Native 查找工程根目录
t_native = time.time()
native_root = None
for sub in os.listdir(PROJECT_ROOT):
    candidate = os.path.join(PROJECT_ROOT, sub)
    if os.path.isdir(os.path.join(candidate, 'global-driver-ios')):
        native_root = candidate; break
if not native_root:
    import glob
    ws = glob.glob(f"{PROJECT_ROOT}/**/*.xcworkspace", recursive=False)
    if ws: native_root = os.path.dirname(ws[0])

if native_root:
    for b in native_repos:
        path = f"{native_root}/{b['repo']}"
        label, status, elapsed = sync_repo(path, b['git_url'], b['branch'], b['repo'])
        report_native.append((label, b['branch'], status, elapsed))
print(f"⏱ Native 仓库同步: {round(time.time()-t_native,1)}s")

# ── 修改 pubspec.yaml ─────────────────────────────────────────
t_cfg = time.time()
def update_pubspec(path):
    try:
        lines = open(path).readlines()
    except FileNotFoundError:
        return
    result, seen, i = [], set(), 0
    while i < len(lines):
        line = lines[i]
        ma = re.match(r'^  (\w+):\s*$', line)
        if ma and i+1 < len(lines):
            mp = re.match(r'^    path: (\.\./\.\./\.\./([^\s/\n]+))', lines[i+1])
            if mp:
                pkg = ma.group(1)
                if pkg not in seen:
                    seen.add(pkg)
                    if pkg in mas_flutter:
                        result += [f'  {pkg}:\n', f'    path: {mp.group(1)}\n']
                    else:
                        result += [f'  # {pkg}:\n', f'  #   path: {mp.group(1)}\n']
                i += 2; continue
        mc = re.match(r'^  # (\w+):\s*$', line)
        if mc and i+1 < len(lines):
            mcp = re.match(r'^  #\s+path: (\.\./\.\./\.\./([^\s/\n]+))', lines[i+1])
            if mcp:
                pkg = mc.group(1)
                if pkg not in seen:
                    seen.add(pkg)
                    if pkg in mas_flutter:
                        result += [f'  {pkg}:\n', f'    path: {mcp.group(1)}\n']
                    else:
                        result += [line, lines[i+1]]
                i += 2; continue
        result.append(line); i += 1
    content = ''.join(result)
    for pkg, repo in mas_flutter.items():
        if pkg not in seen:
            lp = f'../../../{repo}'
            content = re.sub(r'(\ndependency_overrides:.*?)(\nflutter:)',
                lambda m,p=pkg,lp=lp: m.group(1)+f'\n  {p}:\n    path: {lp}\n'+m.group(2),
                content, flags=re.DOTALL)
    open(path, 'w').write(content)

db = f"{PROJECT_ROOT}/driver_business"
update_pubspec(f"{db}/flavor/brazil/pubspec.yaml")
update_pubspec(f"{db}/flavor/global/pubspec.yaml")

# ── 修改 Podfile ──────────────────────────────────────────────
def parse_onepods(onepods_path, repo):
    mh, subspecs = True, None
    try:
        content = open(onepods_path).read()
        for m in re.finditer(r"pod_one\s+'" + re.escape(repo) + r"'([^\n]*)", content):
            line = m.group(0)
            if 'modular_headers: false' in line: mh = False
            sm = re.search(r'subspecs:\s*\[([^\]]+)\]', line)
            if sm: subspecs = [s.strip().strip('"\'') for s in sm.group(1).split(',')]
            break
    except FileNotFoundError:
        pass
    return mh, subspecs

if native_root:
    podfile_path = f"{native_root}/Podfile"
    onepods_path = f"{native_root}/global-driver-ios/OnePods.rb"
    lines = open(podfile_path).readlines()
    result, seen_pods = [], set()
    for line in lines:
        # taco_install_flutter_pods 无论是否激活，一律保持原样不注释
        if 'taco_install_flutter_pods' in line:
            result.append(line); continue
        m = re.match(r'^(\s*)pod \'([^\']+)\', :path => \'([^\']+\.podspec)\'', line)
        if m:
            pname = m.group(2)
            if pname in seen_pods: continue
            seen_pods.add(pname)
            if pname not in mas_native:
                result.append(m.group(1)+'#'+line.lstrip()); continue
        result.append(line)
    missing = mas_native - seen_pods
    if missing:
        ins = [f'  # {TASK_ID}']
        for repo in missing:
            mh, sps = parse_onepods(onepods_path, repo)
            ps = f'{repo}/{repo}.podspec'
            mhs = 'true' if mh else 'false'
            if sps:
                sp_str = ', '.join(f'"{s}"' for s in sps)
                ins.append(f"  pod '{repo}', :path => '{ps}', :inhibit_warnings => false, :subspecs => [{sp_str}], :modular_headers => {mhs}")
            else:
                ins.append(f"  pod '{repo}', :path => '{ps}', :inhibit_warnings => false, :modular_headers => {mhs}")
        ins_block = '\n'.join(ins) + '\n'
        content = ''.join(result)
        content = re.sub(r'(\s*load_\w+\(\))', ins_block + r'\1', content, count=1)
        open(podfile_path, 'w').write(content)
    else:
        open(podfile_path, 'w').write(''.join(result))
print(f"⏱ 配置文件更新: {round(time.time()-t_cfg,1)}s")

# ── 最终报告 ──────────────────────────────────────────────────
print(f"\n{'='*50}")
print(f"✅ 全部完成  ⏱ 总耗时: {round(time.time()-t_total,1)}s\n")
print("### Flutter 仓库")
print("| 仓库 | 分支 | 状态 | 耗时 |")
print("|------|------|------|------|")
for repo,branch,status,elapsed in report_flutter:
    print(f"| `{repo}` | `{branch}` | {status} | {elapsed}s |")
print("\n### Native 仓库")
print("| 仓库 | 分支 | 状态 | 耗时 |")
print("|------|------|------|------|")
for repo,branch,status,elapsed in report_native:
    print(f"| `{repo}` | `{branch}` | {status} | {elapsed}s |")
print("\n⚠️ 后续操作:")
print(f"  Flutter: cd {db}/flavor/brazil && flutter pub get")
if native_root: print(f"  Native:  cd {native_root} && pod install")
EOF
```

## 错误处理

- API 返回 `code != 0` 或"非法请求" → 提示更新 `~/.claude/mas-token.txt`
- git 操作失败 → 标记 ❌，继续处理其他仓库
- 找不到 native_root → 提示用户手动指定路径后重新执行第三步
- 配置文件缺失 → 提示用户按说明生成后重试

## 注意事项

- componentType 3/4 = Flutter，其他 = Native
- Flutter 仓库直接在 PROJECT_ROOT/<repo_name> 下查找
- Native 仓库在含 global-driver-ios 目录的子目录下查找
- pubspec 只处理 `path: ../../../xxx`，不动内部路径（如 `../../core`）
- Podfile 的 modular_headers/subspecs 从 global-driver-ios/OnePods.rb 读取
- `--debug` 参数：在第二步额外打印原始 JSON 响应
