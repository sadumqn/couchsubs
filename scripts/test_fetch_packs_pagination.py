# SPDX-License-Identifier: AGPL-3.0-only
"""Fail closed when R2 paginated listings contain broken continuation metadata."""
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("fetch-packs.py")
SPEC = importlib.util.spec_from_file_location("fetch_packs_pagination", SCRIPT)
fetch_packs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fetch_packs)


class PaginationTests(unittest.TestCase):
    def test_truncated_listing_without_continuation_token_fails_instead_of_looping(self):
        xml = (b'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
               b'<IsTruncated>true</IsTruncated><Contents><Key>bundled/a.json.gz</Key>'
               b'<Size>10</Size></Contents></ListBucketResult>')
        with patch.object(fetch_packs, "request", side_effect=[xml, AssertionError("repeated first page")]) as request:
            with self.assertRaisesRegex(ValueError, "continuation"):
                fetch_packs.list_keys({}, "bundled/")
            self.assertEqual(request.call_count, 1)

    def test_repeated_continuation_token_fails_instead_of_looping(self):
        def page(token):
            return ('<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
                    '<IsTruncated>true</IsTruncated>'
                    '<NextContinuationToken>' + token + '</NextContinuationToken>'
                    '</ListBucketResult>').encode()
        with patch.object(fetch_packs, "request", side_effect=[page("same"), page("same"),
                AssertionError("repeated page")]) as request:
            with self.assertRaisesRegex(ValueError, "continuation"):
                fetch_packs.list_keys({}, "bundled/")
            self.assertEqual(request.call_count, 2)


if __name__ == "__main__":
    unittest.main()
