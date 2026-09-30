import importlib.util
import io
import os
import pathlib
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('deploy', pathlib.Path(__file__).resolve().parents[1] / 'ops/auto-deploy.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


def archive(extra=None):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w') as tf:
        for name in ['index.html', 'app.js', 'style.css', 'site-config.js']:
            info = tarfile.TarInfo('public/' + name)
            info.size = 2
            tf.addfile(info, io.BytesIO(b'ok'))
        if extra:
            tf.addfile(extra, io.BytesIO(b''))
    data.seek(0)
    return data


class DeployTests(unittest.TestCase):
    def test_valid_public_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            deploy.unpack(archive(), root)
            self.assertEqual((root / 'public/index.html').read_bytes(), b'ok')

    def test_rejects_secrets_traversal_links_and_server_files(self):
        cases = [tarfile.TarInfo(name) for name in ['public/.env', 'public/../escape.txt', 'ops/server.py', 'public/private.key']]
        link = tarfile.TarInfo('public/link.html')
        link.type = tarfile.SYMTYPE
        link.linkname = '/etc/passwd'
        cases.append(link)
        for member in cases:
            with self.subTest(path=member.name), tempfile.TemporaryDirectory() as tmp:
                with self.assertRaises(ValueError):
                    deploy.unpack(archive(member), pathlib.Path(tmp))

    def test_failed_live_check_restores_previous_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            previous, new = [base / 'releases' / (char * 40) for char in ('a', 'b')]
            previous.mkdir(parents=True)
            new.mkdir()
            (base / 'current').symlink_to(previous)
            def fail():
                self.assertEqual(os.readlink(base / 'current'), str(new))
                raise RuntimeError('Live check failed')
            with self.assertRaises(RuntimeError):
                deploy.activate(base, new, fail)
            self.assertEqual(os.readlink(base / 'current'), str(previous))


if __name__ == '__main__':
    unittest.main()
