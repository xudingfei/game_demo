#!/usr/bin/env python3
"""GitLab code migration, one bare repository at a time. Python 3.9+, macOS/Linux."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import contextlib
import fcntl
import getpass
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

GIB = 1024 ** 3

class MigrationError(Exception):
    pass

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise MigrationError('服务器要求重定向，请直接配置最终 GitLab 地址。')

class API:
    def __init__(self, base, token):
        self.base = base.rstrip('/')
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())

    def call(self, method, endpoint, data=None, missing=False):
        req = urllib.request.Request(
            self.base + '/api/v4/' + endpoint,
            data=json.dumps(data).encode() if data is not None else None,
            headers={'PRIVATE-TOKEN': self.token, 'Content-Type': 'application/json'},
            method=method)
        for attempt in range(4):
            try:
                with self.opener.open(req, timeout=60) as r:
                    return json.load(r)
            except urllib.error.HTTPError as e:
                if missing and e.code == 404:
                    return None
                if method == 'GET' and e.code in (429, 502, 503, 504) and attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                body = e.read(2048).decode(errors='replace').replace(self.token, '[REDACTED]')
                raise MigrationError(f'API {method} {endpoint}: HTTP {e.code}: {body}') from None
            except urllib.error.URLError as e:
                raise MigrationError(f'API 连接失败: {e.reason}') from None
        raise MigrationError('API 重试失败')

    def pages(self, endpoint):
        page = 1
        while True:
            sep = '&' if '?' in endpoint else '?'
            rows = self.call('GET', f'{endpoint}{sep}per_page=100&page={page}')
            if not rows:
                return
            yield from rows
            page += 1


class ManifestSource:
    """Read source metadata captured from GitLab pages; authenticate Git with a password."""
    def __init__(self, base, password, username, manifest):
        self.base, self.token, self.git_user = base.rstrip('/'), password, username
        self.projects = manifest['projects']
        if manifest.get('source', '').rstrip('/') != self.base:
            raise MigrationError('网页清单的源地址与 --source 不一致')
        self.by_id = {}
        for p in self.projects:
            parts = p['path_with_namespace'].split('/')
            if len(parts) < 2 or any(x in ('', '.', '..') for x in parts):
                raise MigrationError('网页清单包含不合法的项目路径')
            if str(p['id']) in self.by_id:
                raise MigrationError('网页清单包含重复项目 ID')
            self.by_id[str(p['id'])] = p

    def call(self, method, endpoint, data=None, missing=False):
        if method != 'GET':
            raise MigrationError('网页清单模式不允许修改源 GitLab')
        if endpoint == 'user':
            return {'id': 'web:' + self.git_user, 'username': self.git_user}
        if endpoint.startswith('projects/'):
            # Manifest IDs may be synthetic path IDs containing slashes.
            pid = endpoint[len('projects/'):].split('?')[0]
            return self.by_id[pid]
        raise MigrationError('网页清单不支持此源端查询')

    def pages(self, endpoint):
        if not endpoint.startswith('projects?'):
            raise MigrationError('网页清单不支持此源端查询')
        yield from self.projects


def encoded(path):
    return urllib.parse.quote(path, safe='')


def save(path, obj):
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n')
    os.replace(tmp, path)


def refs(text):
    result = {}
    for line in text.splitlines():
        fields = line.split()
        if len(fields) == 2:
            sha, name = fields
            if name.startswith(('refs/heads/', 'refs/tags/')) and not name.endswith('^{}'):
                result[name] = sha
    return result


def compatible(source, dest):
    # A partial previous run is safe only when every existing ref is identical.
    if any(source.get(name) != sha for name, sha in dest.items()):
        raise MigrationError('目标已有不同的分支/标签：停止此项目，不覆盖或删除目标代码。')


def target_path(project, target_user):
    ns = project['namespace']
    if ns['kind'] == 'user' and ns['full_path'] != target_user:
        return 'migrated-users/' + ns['full_path'] + '/' + project['path']
    return project['path_with_namespace']


def ensure_namespace(api, path, own_user):
    if path == own_user:
        matches = [n for n in api.pages('namespaces?search=' + encoded(path))
                   if n.get('full_path') == path and n.get('kind') == 'user']
        if len(matches) != 1:
            raise MigrationError('无法定位目标当前用户的个人命名空间')
        return matches[0]['id']
    parent = None
    current = []
    for segment in path.split('/'):
        current.append(segment)
        group = api.call('GET', 'groups/' + encoded('/'.join(current)), missing=True)
        if group is None:
            body = {'name': segment, 'path': segment, 'visibility': 'private'}
            if parent is not None:
                body['parent_id'] = parent
            group = api.call('POST', 'groups', body)
        parent = group['id']
    return parent


class Runner:
    def __init__(self, scratch, reserve, askpass, secrets=()):
        self.scratch, self.reserve, self.askpass = scratch, reserve, askpass
        self.secrets = secrets

    def run(self, args, cwd=None, token='', user='oauth2'):
        if shutil.disk_usage(self.scratch).free < self.reserve:
            raise MigrationError('可用磁盘已低于保留阈值。')
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(('GIT_', 'GLM_', 'SRC_TOKEN', 'DST_TOKEN'))}
        bundled_lfs = Path(__file__).resolve().parent / 'bin'
        if bundled_lfs.is_dir():
            env['PATH'] = str(bundled_lfs) + os.pathsep + env.get('PATH', '')
        env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
                   GIT_TERMINAL_PROMPT='0', GIT_ASKPASS=str(self.askpass),
                   GLM_TOKEN=token, GLM_USER=user, GIT_LFS_SKIP_SMUDGE='1', LC_ALL='C')
        command = ['git', '-c', 'credential.helper=', '-c', 'http.followRedirects=false',
                   '-c', 'http.lowSpeedLimit=1024', '-c', 'http.lowSpeedTime=120',
                   '-c', 'core.hooksPath=/dev/null', '-c', 'gc.auto=0',
                   '-c', 'pack.threads=1', '-c', 'pack.windowMemory=128m',
                   '-c', 'lfs.concurrenttransfers=1'] + list(args)
        with tempfile.TemporaryFile(dir=self.scratch) as output:
            p = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                 stdout=output, stderr=output, start_new_session=True)
            start = last = time.monotonic()
            try:
                while p.poll() is None:
                    if shutil.disk_usage(self.scratch).free < self.reserve:
                        raise MigrationError('磁盘低于保留阈值，已中止本项目并清理临时副本。')
                    now = time.monotonic()
                    if now - start > 24 * 3600:
                        raise MigrationError('单条 Git 命令超过 24 小时，已中止。')
                    if now - last > 30:
                        print(f'    仍在传输/处理，可用 {shutil.disk_usage(self.scratch).free/GIB:.1f} GiB', flush=True)
                        last = now
                    time.sleep(0.25)
            except BaseException:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(p.pid, signal.SIGKILL)
                p.wait()
                raise
            output.seek(0)
            if p.returncode:
                output.seek(0, 2)
                output.seek(max(0, output.tell() - 4000))
                message = output.read().decode(errors='replace')
                for secret in self.secrets:
                    if secret:
                        message = message.replace(secret, '[REDACTED]')
                raise MigrationError('Git 失败：' + message)
            return output.read().decode(errors='replace')


def transfer(source, dest, project, dest_path, target_user, runner, state, statefile, sync=False):
    pid = str(project['id'])
    detail = source.call('GET', 'projects/' + pid + '?statistics=true')
    stats = detail.get('statistics') or {}
    estimate = 2 * ((stats.get('repository_size') or 0) + (stats.get('lfs_objects_size') or 0))
    if shutil.disk_usage(runner.scratch).free < runner.reserve + estimate:
        raise MigrationError(f'空间不足：本项目估算需要 {estimate/GIB:.1f} GiB 临时空间，另需保留 {runner.reserve/GIB:.1f} GiB。')
    su = source.base + '/' + urllib.parse.quote(project['path_with_namespace'], safe='/') + '.git'
    du = dest.base + '/' + urllib.parse.quote(dest_path, safe='/') + '.git'
    with tempfile.TemporaryDirectory(prefix='repo-', dir=runner.scratch) as tmp:
        repo = Path(tmp) / 'repo.git'
        runner.run(['init', '--bare', str(repo)])
        runner.run(['remote', 'add', 'source', su], cwd=repo)
        runner.run(['remote', 'add', 'target', du], cwd=repo)
        # Explicit endpoints ignore custom .lfsconfig URLs in source content.
        runner.run(['config', 'remote.source.lfsurl', su + '/info/lfs'], cwd=repo)
        runner.run(['config', 'remote.target.lfsurl', du + '/info/lfs'], cwd=repo)
        runner.run(['config', 'remote.target.lfspushurl', du + '/info/lfs'], cwd=repo)
        print('    下载分支、标签及历史', flush=True)
        runner.run(['fetch', '--no-tags', 'source', '+refs/heads/*:refs/heads/*',
                    '+refs/tags/*:refs/tags/*'], cwd=repo, token=source.token,
                   user=getattr(source, 'git_user', 'oauth2'))
        expected = refs(runner.run(['for-each-ref', '--format=%(objectname) %(refname)',
                                   'refs/heads/', 'refs/tags/'], cwd=repo))
        runner.run(['fsck', '--full'], cwd=repo)
        target = dest.call('GET', 'projects/' + encoded(dest_path), missing=True)
        record = state['projects'].get(pid, {})
        if target:
            existing = refs(runner.run(['ls-remote', '--refs', 'target', 'refs/heads/*', 'refs/tags/*'],
                                      cwd=repo, token=dest.token))
            if not sync:
                compatible(expected, existing)
            if existing and record.get('target_id') != target['id']:
                raise MigrationError('目标仓库非空且并非此迁移记录创建/接管的项目；为避免改动现有项目，已跳过。')
            if target.get('archived'):
                raise MigrationError('目标项目已归档，请在目标端确认是否解档后重试。')
            if target.get('builds_access_level') != 'disabled':
                raise MigrationError('目标已有项目启用了 CI，请先在项目设置中禁用 CI/CD 后重试。')
        else:
            namespace = ensure_namespace(dest, dest_path.rsplit('/', 1)[0], target_user)
            target = dest.call('POST', 'projects', {
                'name': project['name'], 'path': dest_path.rsplit('/', 1)[1],
                'namespace_id': namespace, 'description': detail.get('description') or '',
                'visibility': 'private', 'initialize_with_readme': False,
                'builds_access_level': 'disabled', 'lfs_enabled': True})
        state['projects'][pid] = {'target_id': target['id'], 'path': dest_path, 'status': 'in_progress'}
        save(statefile, state)
        if expected:
            print('    迁移全部历史引用的 LFS 文件', flush=True)
            runner.run(['lfs', 'fetch', '--all', 'source'], cwd=repo, token=source.token,
                       user=getattr(source, 'git_user', 'oauth2'))
            runner.run(['lfs', 'push', '--all', 'target'], cwd=repo, token=dest.token)
            print('    上传分支和标签', flush=True)
            specs = []
            if any(r.startswith('refs/heads/') for r in expected):
                specs.append('refs/heads/*:refs/heads/*')
            if any(r.startswith('refs/tags/') for r in expected):
                specs.append('refs/tags/*:refs/tags/*')
            runner.run(['push', '--atomic', 'target'] + specs, cwd=repo, token=dest.token)
        actual = refs(runner.run(['ls-remote', '--refs', 'target', 'refs/heads/*', 'refs/tags/*'],
                                cwd=repo, token=dest.token))
        if actual != expected:
            raise MigrationError('目标分支/标签 SHA 校验不一致，未标记完成。')
        latest = refs(runner.run(['ls-remote', '--refs', 'source', 'refs/heads/*', 'refs/tags/*'],
                                cwd=repo, token=source.token, user=getattr(source, 'git_user', 'oauth2')))
        if latest != expected:
            raise MigrationError('源仓库迁移期间发生变化；请暂停提交后重新迁移。')
        if detail.get('default_branch') and 'refs/heads/' + detail['default_branch'] in expected:
            dest.call('PUT', 'projects/' + str(target['id']), {'default_branch': detail['default_branch']})
        state['projects'][pid].update(status='done', refs=expected, completed_at=time.strftime('%Y-%m-%d %H:%M:%S'))
        save(statefile, state)
    print('    完成：SHA 校验通过，临时副本已清理。', flush=True)


def transient_git_error(message):
    """Recognize source/target gateway failures that are safe to retry."""
    markers = ('HTTP 500', 'HTTP 502', 'HTTP 503', 'HTTP 504',
               'RPC failed', 'expected flush', 'expected \'packfile\'',
               'early EOF', 'remote end hung up')
    return any(marker in message for marker in markers)


def main():
    parser = argparse.ArgumentParser(description='GitLab 串行代码迁移。默认仅生成清单；--execute 才写入目标。')
    parser.add_argument('--source', default='https://bhgitlab.jszbtb.com')
    parser.add_argument('--target', default='http://180.100.211.129:29016')
    parser.add_argument('--source-manifest', type=Path, help='从已登录源网页获取的项目清单；启用源账号密码模式')
    parser.add_argument('--source-user', default='root', help='网页清单模式使用的源 Git 用户名')
    parser.add_argument('--work-dir', type=Path, default=Path(__file__).resolve().parent / 'migration-work')
    parser.add_argument('--reserve-gb', type=float, default=8)
    parser.add_argument('--project', action='append', help='只处理指定完整路径，可重复使用')
    parser.add_argument('--execute', action='store_true', help='实际执行迁移')
    parser.add_argument('--sync', action='store_true', help='比较源端分支/标签 SHA，只同步发生变化的项目')
    args = parser.parse_args()
    if args.reserve_gb < 2:
        parser.error('--reserve-gb 至少为 2')
    for base in (args.source, args.target):
        u = urllib.parse.urlsplit(base)
        if u.scheme not in ('http', 'https') or not u.netloc or u.username or u.password or u.query or u.fragment:
            parser.error('地址必须是无用户名、密码、查询参数的 HTTP(S) GitLab 根地址')
    if args.source.rstrip('/') == args.target.rstrip('/'):
        parser.error('源和目标不能相同')
    os.umask(0o077)
    args.work_dir = args.work_dir.expanduser().resolve()
    args.work_dir.mkdir(parents=True, exist_ok=True)
    with (args.work_dir / 'run.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise MigrationError('同一工作目录中已有迁移程序正在运行') from None
        source_token = (getpass.getpass('源 GitLab 密码（隐藏输入）: ') if args.source_manifest else
                        os.environ.get('SRC_TOKEN') or getpass.getpass('源 GitLab 的 Personal Access Token（隐藏输入）: '))
        target_token = os.environ.get('DST_TOKEN') or getpass.getpass('目标 GitLab 的 Personal Access Token（隐藏输入）: ')
        if not source_token or not target_token:
            raise MigrationError('必须提供源端认证凭据和目标端令牌。')
        source = (ManifestSource(args.source, source_token, args.source_user,
                                 json.loads(args.source_manifest.read_text())) if args.source_manifest else
                  API(args.source, source_token))
        dest = API(args.target, target_token)
        source_user, target_user = source.call('GET', 'user'), dest.call('GET', 'user')
        binding = {'source': source.base, 'target': dest.base,
                   'source_user': source_user['id'], 'target_user': target_user['id']}
        statefile = args.work_dir / 'state.json'
        state = json.loads(statefile.read_text()) if statefile.exists() else {'binding': binding, 'projects': {}}
        if state.get('binding') != binding:
            raise MigrationError('工作目录属于另一组服务器或账户，请使用新的 --work-dir。')
        projects = list(source.pages('projects?statistics=true&order_by=id&sort=asc'))
        if args.project:
            wanted = set(args.project)
            projects = [p for p in projects if p['path_with_namespace'] in wanted]
            missing = wanted - {p['path_with_namespace'] for p in projects}
            if missing:
                raise MigrationError('找不到或无权访问项目: ' + ', '.join(sorted(missing)))
        plan = [{'source_id': p['id'], 'source': p['path_with_namespace'],
                 'target': target_path(p, target_user['username']),
                 'statistics': p.get('statistics') or {}} for p in projects]
        if len({p['target'] for p in plan}) != len(plan):
            raise MigrationError('个人项目映射与源群组路径冲突，需要调整目标路径规则。')
        save(args.work_dir / 'plan.json', {'binding': binding, 'projects': plan})
        print(f'发现 {len(projects)} 个可见项目；可用空间 {shutil.disk_usage(args.work_dir).free/GIB:.1f} GiB')
        for item in plan:
            s = item['statistics']
            size = f"仓库 {s.get('repository_size', 0)/GIB:.2f} / LFS {s.get('lfs_objects_size', 0)/GIB:.2f} GiB" if s else '大小未知，执行时监控空间'
            print(f"  {item['source']} → {item['target']}  ({size})")
        if not args.execute:
            print(f'仅预览，未下载代码或修改目标。清单: {args.work_dir / "plan.json"}')
            return 0
        lfs_env = os.environ.copy()
        bundled_lfs = Path(__file__).resolve().parent / 'bin'
        if bundled_lfs.is_dir():
            lfs_env['PATH'] = str(bundled_lfs) + os.pathsep + lfs_env.get('PATH', '')
        if subprocess.run(['git', 'lfs', 'version'], env=lfs_env,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
            raise MigrationError('找不到 Git LFS；请运行 brew install git-lfs，或保留程序包中的 bin/git-lfs。')
        scratch = args.work_dir / 'scratch'
        scratch.mkdir(exist_ok=True)
        # Only this private, lock-protected scratch directory is disposable.
        for old in scratch.glob('repo-*'):
            if old.is_dir() and not old.is_symlink():
                shutil.rmtree(old)
        askpass = scratch / 'askpass.sh'
        askpass.write_text('#!/bin/sh\ncase "$1" in\n*Username*) printf "%s\\n" "$GLM_USER" ;;\n*Password*) printf "%s\\n" "$GLM_TOKEN" ;;\n*) exit 1 ;;\nesac\n')
        askpass.chmod(0o700)
        runner = Runner(scratch, args.reserve_gb * GIB, askpass, (source_token, target_token))
        changed_ids = None
        if args.sync:
            changed_ids = set()
            print('开始比较源端分支/标签 SHA…', flush=True)
            def compare_project(p):
                pid = str(p['id'])
                record = state['projects'].get(pid, {})
                if record.get('status') != 'done':
                    return pid, p['path_with_namespace'], True, None
                su = source.base + '/' + urllib.parse.quote(p['path_with_namespace'], safe='/') + '.git'
                latest = None
                for attempt in range(3):
                    try:
                        latest = refs(runner.run(
                            ['ls-remote', '--refs', su, 'refs/heads/*', 'refs/tags/*'],
                            token=source.token, user=getattr(source, 'git_user', 'oauth2')))
                        break
                    except MigrationError as e:
                        if attempt == 2 or not transient_git_error(str(e)):
                            return pid, p['path_with_namespace'], True, 'check failed'
                        time.sleep(2 ** attempt)
                return pid, p['path_with_namespace'], latest is not None and latest != record.get('refs', {}), None
            with ThreadPoolExecutor(max_workers=8) as pool:
                futures = [pool.submit(compare_project, p) for p in projects]
                for future in as_completed(futures):
                    pid, path, changed, error = future.result()
                    if changed:
                        changed_ids.add(pid)
                        if error:
                            print(f'    SHA 检查失败，按项目重试：{path}', flush=True)
                        else:
                            print(f'    检测到变更：{path}', flush=True)
            print(f'检测完成：{len(changed_ids)} 个项目需要同步。', flush=True)
        failures = []
        for p, item in zip(projects, plan):
            print(f"\n[{p['id']}] {p['path_with_namespace']}", flush=True)
            if args.sync and str(p['id']) not in changed_ids:
                print('    源端 SHA 未变化，跳过。')
                continue
            if not args.sync and state['projects'].get(str(p['id']), {}).get('status') == 'done':
                print('    已完成，按记录跳过（非持续同步）。')
                continue
            try:
                for attempt in range(3):
                    try:
                        transfer(source, dest, p, item['target'], target_user['username'], runner, state, statefile, sync=args.sync)
                        break
                    except MigrationError as e:
                        if attempt == 2 or not transient_git_error(str(e)):
                            raise
                        print(f'    网关/网络错误，{attempt + 1}/2 秒后重试本项目', flush=True)
                        time.sleep(2 ** attempt)
            except (MigrationError, OSError) as e:
                msg = str(e).replace(source_token, '[REDACTED]').replace(target_token, '[REDACTED]')
                print('    失败/跳过：' + msg, flush=True)
                failures.append({'project': p['path_with_namespace'], 'error': msg})
        save(args.work_dir / 'failures.json', failures)
        print(f'\n结束。本轮失败/跳过 {len(failures)} 个。记录: {statefile}')
        return 1 if failures else 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('\n已中断；再次运行可跳过已完成项目。', file=sys.stderr)
        sys.exit(130)
    except (MigrationError, OSError, ValueError) as e:
        print(f'错误: {e}', file=sys.stderr)
        sys.exit(1)
