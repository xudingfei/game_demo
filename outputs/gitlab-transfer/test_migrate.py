import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import migrate as m


def git(*args, cwd=None):
    return subprocess.check_output(['git', '-c', 'user.name=Test', '-c',
                                   'user.email=test@example.invalid', *args],
                                  cwd=cwd, stderr=subprocess.DEVNULL).decode()

class FakeAPI:
    def __init__(self, base, repo, source=False):
        self.base, self.repo, self.source, self.token = base, repo, source, 'fake-token'
        self.created = False
        self.default = None

    def call(self, method, endpoint, data=None, missing=False):
        if self.source:
            return {'statistics': {}, 'default_branch': 'main', 'description': 'test'}
        if method == 'GET' and endpoint.startswith('groups/'):
            return {'id': 3}
        if method == 'GET':
            return {'id': 99, 'builds_access_level': 'disabled'} if self.created else None
        if method == 'POST':
            git('init', '--bare', str(self.repo))
            self.created = True
            return {'id': 99}
        if method == 'PUT':
            self.default = data['default_branch']
            return {}
        raise AssertionError((method, endpoint))

class LocalRunner(m.Runner):
    """Run real Git locally; stand in for LFS because it is absent on this Mac."""
    def __init__(self, scratch, source, target):
        super().__init__(scratch, 0, scratch / 'unused')
        self.source, self.target, self.lfs_calls = source, target, []

    def run(self, args, **kw):
        args = list(args)
        if args[0] == 'lfs':
            self.lfs_calls.append(args)
            return ''
        if args[:2] == ['remote', 'add']:
            args[-1] = str(self.source if args[2] == 'source' else self.target)
        return super().run(args, **kw)

class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.scratch = self.root / 'scratch'
        self.scratch.mkdir()
        self.src = self.root / 'source'
        self.dst = self.root / 'target.git'
        git('init', '-b', 'main', str(self.src))
        (self.src / 'hello.txt').write_text('hello\n')
        git('add', '.', cwd=self.src)
        git('commit', '-m', 'first', cwd=self.src)
        git('tag', '-a', 'v1', '-m', 'release', cwd=self.src)
        git('branch', 'feature', cwd=self.src)
        self.source = FakeAPI('https://source.invalid', self.src, True)
        self.dest = FakeAPI('https://target.invalid', self.dst)
        self.runner = LocalRunner(self.scratch, self.src, self.dst)
        self.state = {'projects': {}}
        self.statefile = self.root / 'state.json'
        self.project = {'id': 1, 'path_with_namespace': 'team/app', 'path': 'app', 'name': 'app'}

    def tearDown(self):
        self.tmp.cleanup()

    def transfer(self):
        m.transfer(self.source, self.dest, self.project, 'team/app', 'root',
                   self.runner, self.state, self.statefile)

    def test_real_git_transfer_and_cleanup(self):
        self.transfer()
        expected = m.refs(git('show-ref', cwd=self.src))
        self.assertEqual(expected, m.refs(git('show-ref', cwd=self.dst)))
        self.assertEqual(self.dest.default, 'main')
        self.assertEqual(json.loads(self.statefile.read_text())['projects']['1']['status'], 'done')
        self.assertEqual(self.runner.lfs_calls, [['lfs', 'fetch', '--all', 'source'], ['lfs', 'push', '--all', 'target']])
        self.assertFalse(list(self.scratch.glob('repo-*')))

    def test_owned_partial_retry(self):
        self.transfer()
        git('update-ref', '-d', 'refs/heads/feature', cwd=self.dst)
        self.state['projects']['1']['status'] = 'in_progress'
        self.transfer()
        self.assertEqual(m.refs(git('show-ref', cwd=self.src)), m.refs(git('show-ref', cwd=self.dst)))

    def test_conflict_does_not_overwrite(self):
        self.transfer()
        before = git('rev-parse', 'refs/heads/main', cwd=self.dst)
        git('update-ref', 'refs/heads/only-target', before.strip(), cwd=self.dst)
        with self.assertRaisesRegex(m.MigrationError, '目标已有不同'):
            self.transfer()
        self.assertEqual(before, git('rev-parse', 'refs/heads/main', cwd=self.dst))
        self.assertFalse(list(self.scratch.glob('repo-*')))

    def test_unowned_repository_is_rejected(self):
        self.transfer()
        self.state['projects'].clear()
        with self.assertRaisesRegex(m.MigrationError, '目标仓库非空'):
            self.transfer()

    def test_low_disk_prevents_git(self):
        runner = m.Runner(self.scratch, 100, self.scratch / 'askpass')
        with patch('migrate.shutil.disk_usage', return_value=shutil._ntuple_diskusage(1000, 950, 50)):
            with patch('migrate.subprocess.Popen') as popen:
                with self.assertRaises(m.MigrationError):
                    runner.run(['version'])
                popen.assert_not_called()

    def test_low_disk_kills_running_process(self):
        runner = m.Runner(self.scratch, 100, self.scratch / 'askpass')
        high = shutil._ntuple_diskusage(1000, 100, 900)
        low = shutil._ntuple_diskusage(1000, 950, 50)
        with patch('migrate.shutil.disk_usage', side_effect=[high, low]):
            with patch('migrate.subprocess.Popen') as popen, patch('migrate.os.killpg') as kill:
                popen.return_value.poll.return_value = None
                with self.assertRaisesRegex(m.MigrationError, '磁盘低于'):
                    runner.run(['fetch'])
                kill.assert_called_once()
                popen.return_value.wait.assert_called_once()

    def test_annotated_tags_and_namespace_mapping(self):
        self.assertEqual(m.refs('abc refs/tags/v1\ndef refs/tags/v1^{}\nxyz refs/merge-requests/1/head'), {'refs/tags/v1': 'abc'})
        p = {'namespace': {'kind': 'user', 'full_path': 'alice'}, 'path': 'demo', 'path_with_namespace': 'alice/demo'}
        self.assertEqual(m.target_path(p, 'root'), 'migrated-users/alice/demo')
        self.assertEqual(m.target_path(p, 'alice'), 'alice/demo')

    def test_manifest_password_source(self):
        p = dict(self.project, default_branch='main')
        source = m.ManifestSource('https://source.invalid', 'test-password', 'root',
                                  {'source': 'https://source.invalid', 'projects': [p]})
        self.assertEqual(source.call('GET', 'projects/1?statistics=true'), p)
        self.assertEqual(source.git_user, 'root')
        self.assertEqual(list(source.pages('projects?statistics=true')), [p])
        with self.assertRaises(m.MigrationError):
            source.call('POST', 'projects')
        with self.assertRaises(m.MigrationError):
            m.ManifestSource('https://wrong.invalid', 'password', 'root',
                             {'source': 'https://source.invalid', 'projects': [p]})

    def test_lfs_failure_not_marked_done_and_cleans(self):
        real = self.runner.run
        def fail(args, **kw):
            if list(args)[:2] == ['lfs', 'push']:
                raise m.MigrationError('LFS upload failed')
            return real(args, **kw)
        with patch.object(self.runner, 'run', side_effect=fail):
            with self.assertRaisesRegex(m.MigrationError, 'LFS upload failed'):
                self.transfer()
        self.assertEqual(self.state['projects']['1']['status'], 'in_progress')
        self.assertFalse(list(self.scratch.glob('repo-*')))
        self.assertEqual(git('for-each-ref', cwd=self.dst), '')

if __name__ == '__main__':
    unittest.main()
