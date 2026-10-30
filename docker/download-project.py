#!/usr/bin/env python3
"""Cache Drive discovery and resume project files after network interruptions."""

import json
import os
import re
from pathlib import Path
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import parse_qs, urlparse

import gdown
import requests
from requests.exceptions import RequestException, SSLError
# These helpers are from the pinned gdown 6.4.2 release in setup.sh. Cache
# individual folders so a late Drive error does not restart the entire crawl.
from gdown.download import _get_session, _sanitize_filename
from gdown.download_folder import _parse_embedded_folder_view

# setup.sh rebuilds the editor/project locally. Saved logs, crash dumps,
# generated IDE files and another machine's build cache are not inputs.
PROJECT_DIRECTORIES = {"Config", "Content", "Plugins", "Source"}


def download_direct(url, target, timeout, resume=True):
    """Download a Drive attachment without scraping its public preview page."""
    file_id = parse_qs(urlparse(url).query)["id"][0]
    if not re.fullmatch(r"[A-Za-z0-9_-]+", file_id):
        raise ValueError("Invalid Google Drive file ID")
    partial = target.with_name(target.name + ".drive.part")
    offset = partial.stat().st_size if resume and partial.exists() else 0
    headers = {"Accept-Encoding": "identity"}
    if offset:
        headers["Range"] = f"bytes={offset}-"
    with requests.get(
        "https://drive.usercontent.google.com/download",
        params={"id": file_id, "export": "download", "confirm": "t"},
        headers=headers, stream=True, timeout=timeout,
    ) as response:
        if offset and response.status_code == 416:
            # A completed-but-unpublished partial or a changed remote size:
            # restart and validate a fresh response instead of looping on 416.
            response.close()
            return download_direct(url, target, timeout, resume=False)
        response.raise_for_status()
        if not response.headers.get("Content-Disposition", "").lower().startswith("attachment"):
            raise gdown.FileURLRetrievalError(
                f"Drive returned a page instead of an attachment for {target.name}"
            )
        total = None
        if response.status_code == 206:
            match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)",
                                 response.headers.get("Content-Range", ""))
            if not match or int(match[1]) != offset or int(match[2]) + 1 != int(match[3]):
                raise gdown.DownloadError(f"Invalid resume response for {target.name}")
            total = int(match[3])
        elif response.status_code == 200:
            offset = 0  # Server ignored Range; replace rather than append.
            if response.headers.get("Content-Length"):
                total = int(response.headers["Content-Length"])
        else:
            raise gdown.DownloadError(f"Unexpected HTTP {response.status_code} for {target.name}")
        with partial.open("ab" if offset else "wb") as output:
            for chunk in response.iter_content(chunk_size=256 * 1024):
                output.write(chunk)
        if total is not None and partial.stat().st_size != total:
            raise gdown.DownloadError(f"Incomplete download for {target.name}")
    partial.replace(target)


def project_input(path):
    return path == Path("FlyCo.uproject") or (
        path.parts and path.parts[0] in PROJECT_DIRECTORIES
    )


def discover(data, timeout, retries):
    cache = data / "project-folders"
    cache.mkdir(parents=True, exist_ok=True)
    session, _ = _get_session(
        proxy=None, use_cookies=False,
        user_agent="Mozilla/5.0", cookies_file=None,
    )
    pending = [("1BXd7_2unaK4iHz50_pSFBnJU25b3mYVl", Path())]
    entries = []
    try:
        while pending:
            folder_id, relative = pending.pop()
            saved = cache / f"{folder_id}.json"
            print(f"Listing project folder: {relative}", flush=True)
            if saved.is_file():
                children = json.loads(saved.read_text())
            else:
                for attempt in range(retries + 1):
                    try:
                        _, children = _parse_embedded_folder_view(
                            sess=session, folder_id=folder_id, verify=True, timeout=timeout,
                        )
                        temporary = saved.with_suffix(".json.part")
                        temporary.write_text(json.dumps(children))
                        temporary.replace(saved)
                        break
                    except Exception as error:
                        if attempt == retries:
                            raise
                        print(f"Folder {relative}: {error}; retry {attempt + 1}/{retries}",
                              file=sys.stderr, flush=True)
                        time.sleep(min(2 ** attempt, 10))
            for child_id, name, kind in children:
                path = relative / _sanitize_filename(filename=name)
                if relative == Path():
                    if kind == "application/vnd.google-apps.folder":
                        if name not in PROJECT_DIRECTORIES:
                            continue
                    elif name != "FlyCo.uproject":
                        continue
                if kind == "application/vnd.google-apps.folder":
                    pending.append((child_id, path))
                else:
                    entries.append({"url": f"https://drive.google.com/uc?id={child_id}",
                                    "path": str(path)})
    finally:
        session.close()
    return entries


def main():
    data = Path(sys.argv[1])
    destination = data / "project-download"
    manifest = data / "project-manifest.json"
    timeout = float(os.environ.get("DOWNLOAD_TIMEOUT", "60"))
    retries = int(os.environ.get("DOWNLOAD_RETRIES", "3"))
    jobs = int(os.environ.get("DOWNLOAD_JOBS", "4"))
    if timeout <= 0 or retries < 0 or jobs < 1:
        raise ValueError("DOWNLOAD_TIMEOUT and DOWNLOAD_JOBS must be positive; DOWNLOAD_RETRIES must be nonnegative")

    if manifest.is_file() and manifest.stat().st_size:
        entries = json.loads(manifest.read_text())
        print(f"Using cached project listing: {len(entries)} files", flush=True)
    else:
        entries = discover(data, timeout, retries)
        if not entries:
            raise RuntimeError("Google Drive returned an empty project listing")
        temporary = manifest.with_suffix(".json.part")
        temporary.write_text(json.dumps(entries, indent=2))
        temporary.replace(manifest)

    # Also filter older complete manifests generated by gdown --json.
    entries = [item for item in entries if project_input(Path(item["path"]))]
    if not any(item["path"] == "FlyCo.uproject" for item in entries):
        raise ValueError(f"Project listing lacks FlyCo.uproject: {manifest}")
    for item in entries:
        relative = Path(item["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Unsafe project path: {relative}")

    def download_one(index, item):
        relative = Path(item["path"])
        target = destination / relative
        # Downloads are atomically renamed; avoid a network request
        # even for files already finished on a previous run.
        if target.is_file():
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        print(f"Project [{index}/{len(entries)}]: {relative}", flush=True)
        for attempt in range(retries + 1):
            try:
                download_direct(item["url"], target, timeout)
                print(f"Downloaded: {relative} ({target.stat().st_size} bytes)", flush=True)
                return
            except SSLError as error:
                # gdown does not retry SSL errors, including a transient EOF.
                # Certificate verification failures still fail immediately.
                if "UNEXPECTED_EOF_WHILE_READING" not in str(error) or attempt == retries:
                    raise
                print(f"TLS connection closed for {relative}; retry {attempt + 1}/{retries}",
                      file=sys.stderr, flush=True)
                time.sleep(min(2 ** attempt, 10))
            except (RequestException, gdown.DownloadError) as error:
                # Retry transient HTTP/connection failures and reject Drive
                # error pages. Never publish them as completed project files.
                if attempt == retries:
                    raise
                print(f"Drive download failed for {relative}; retry {attempt + 1}/{retries}: {error}",
                      file=sys.stderr, flush=True)
                time.sleep(min(5 * 2 ** attempt, 30))

    print(f"Downloading {len(entries)} project files with {jobs} workers", flush=True)
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(download_one, index, item)
                   for index, item in enumerate(entries, 1)]
        try:
            for future in as_completed(futures):
                future.result()
        except Exception:
            for future in futures:
                future.cancel()
            raise


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        sys.exit(f"Project download failed: {error}\n"
                 "Downloaded files and the listing are retained; rerun bash docker/setup.sh.")
