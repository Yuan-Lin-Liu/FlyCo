import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch

from requests.exceptions import SSLError

spec = importlib.util.spec_from_file_location(
    "download_project", Path(__file__).resolve().parents[1] / "download-project.py"
)
download_project = importlib.util.module_from_spec(spec)
spec.loader.exec_module(download_project)


class ProjectDownloadTests(unittest.TestCase):
    @staticmethod
    def response(status, content, **headers):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status_code = status
        response.headers = {"Content-Disposition": 'attachment; filename="file"', **headers}
        response.iter_content.return_value = [content]
        return response

    def test_direct_resume_and_ignored_range(self):
        for status in (200, 206, 416):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / "file"
                partial = target.with_name("file.drive.part")
                partial.write_bytes(b"abc")
                response = self.response(
                    status, b"def" if status == 206 else b"abcdef",
                    **({"Content-Range": "bytes 3-5/6"} if status == 206
                       else {"Content-Length": "6"}),
                )
                responses = [response]
                if status == 416:
                    responses.append(self.response(200, b"abcdef", **{"Content-Length": "6"}))
                with patch.object(download_project.requests, "get", side_effect=responses) as get:
                    download_project.download_direct("https://drive.google.com/uc?id=test", target, 5)
                    self.assertEqual(get.call_args_list[0].kwargs["headers"]["Range"], "bytes=3-")
                    if status == 416:
                        self.assertNotIn("Range", get.call_args_list[1].kwargs["headers"])
                self.assertEqual(target.read_bytes(), b"abcdef")
                self.assertFalse(partial.exists())

    def test_direct_rejects_error_pages_truncation_and_bad_ranges(self):
        responses = [
            self.response(200, b"<html>quota exceeded</html>", **{"Content-Disposition": ""}),
            self.response(200, b"abc", **{"Content-Length": "6"}),
            self.response(206, b"def", **{"Content-Range": "bytes 4-6/7"}),
        ]
        for response in responses:
            with tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / "file"
                with patch.object(download_project.requests, "get", return_value=response):
                    with self.assertRaises(download_project.gdown.DownloadError):
                        download_project.download_direct("https://drive.google.com/uc?id=test", target, 5)
                self.assertFalse(target.exists())

    def test_resume_after_folder_and_tls_failures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            listing = Mock(side_effect=[
                TimeoutError("stalled listing"),
                ("FlyCo", [
                    ("project", "FlyCo.uproject", "file"),
                    ("saved", "Saved", "application/vnd.google-apps.folder"),
                    ("source", "Source", "application/vnd.google-apps.folder"),
                ]),
                ("Source", [("code", "Blocks.cpp", "file")]),
            ])
            attempts = []

            def download(url, target, timeout):
                attempts.append(url)
                if len(attempts) == 1:
                    raise SSLError("UNEXPECTED_EOF_WHILE_READING")
                target.write_text("complete")
                self.assertEqual(timeout, 5)
                return str(target)

            with (
                patch.object(sys, "argv", ["download-project.py", directory]),
                patch.dict(os.environ, {"DOWNLOAD_TIMEOUT": "5", "DOWNLOAD_RETRIES": "1", "DOWNLOAD_JOBS": "1"}),
                patch.object(download_project, "_get_session", return_value=(Mock(), "")),
                patch.object(download_project, "_parse_embedded_folder_view", listing),
                patch.object(download_project.time, "sleep"),
                patch.object(download_project, "download_direct", side_effect=download) as fetch,
            ):
                download_project.main()
                self.assertEqual(listing.call_count, 3)
                self.assertEqual(fetch.call_count, 3)
                manifest = root / "project-manifest.json"
                self.assertEqual(len(json.loads(manifest.read_text())), 2)
                self.assertFalse(manifest.with_suffix(".json.part").exists())
                listing.reset_mock()
                fetch.reset_mock()
                download_project.main()
                fetch.assert_not_called()
                listing.assert_not_called()
                # A missing full manifest can be rebuilt from folder caches.
                manifest.unlink()
                download_project.main()
                listing.assert_not_called()
                fetch.assert_not_called()
                # Do not hide or retry invalid certificates as transient EOFs.
                (root / "project-download/FlyCo.uproject").unlink()
                fetch.side_effect = SSLError("CERTIFICATE_VERIFY_FAILED")
                with self.assertRaises(SSLError):
                    download_project.main()
                self.assertEqual(fetch.call_count, 1)
                self.assertTrue(manifest.is_file())
                # A public file may temporarily fail Drive link discovery.
                fetch.reset_mock()
                failures = [download_project.gdown.FileURLRetrievalError("temporary Drive link error")]

                def temporary_link_error(url, target, timeout):
                    if failures:
                        raise failures.pop()
                    return download(url, target, timeout)

                fetch.side_effect = temporary_link_error
                download_project.main()
                self.assertEqual(fetch.call_count, 2)
                self.assertTrue((root / "project-download/FlyCo.uproject").is_file())

    def test_old_listing_filters_generated_files_and_rejects_path_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "project-manifest.json"
            entries = [{"url": "unused", "path": "FlyCo.uproject"},
                       {"url": "unused", "path": "Saved/old.log"}]
            manifest.write_text(json.dumps(entries))
            (root / "project-download").mkdir()
            (root / "project-download/FlyCo.uproject").write_text("complete")
            with (patch.object(sys, "argv", ["download-project.py", directory]),
                  patch.object(download_project, "download_direct") as fetch):
                download_project.main()
                fetch.assert_not_called()
                entries.append({"url": "unused", "path": "Source/../../escape"})
                manifest.write_text(json.dumps(entries))
                with self.assertRaises(ValueError):
                    download_project.main()
                fetch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
