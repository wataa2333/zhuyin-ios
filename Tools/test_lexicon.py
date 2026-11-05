"""Validate the shipped read-only dictionary and its lookup plans without an iOS runtime."""
import pathlib
from contextlib import closing
import sqlite3
import statistics
import time
import unittest

from build_lexicon import encode_sound_key, to_zhuyin, write_database


DATABASE = pathlib.Path(__file__).resolve().parents[1] / "Keyboard" / "Lexicon.sqlite"


def query(db, sounds, tones, completion=False, limit=36):
    key = encode_sound_key(sounds)
    parts = [sound + ("*" if completion and i == len(sounds) - 1 else "")
             + (f"[0{tone}]" if tone else "[0-5]") for i, (sound, tone) in enumerate(zip(sounds, tones))]
    predicate = "sound_key>=? AND sound_key<? AND sound_key<>?" if completion else "sound_key=?"
    args = [len(sounds), key]
    if completion:
        args += [key + "\U0010ffff", key]
    args += [" ".join(parts), limit]
    sql = f"SELECT text,reading,rank FROM entries WHERE syllables=? AND {predicate} AND reading GLOB ? ORDER BY rank LIMIT ?"
    return sql, args


class DictionaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db = sqlite3.connect(DATABASE.as_uri() + "?mode=ro", uri=True)
        cls.db.executescript("PRAGMA query_only=ON; PRAGMA cache_size=-512; PRAGMA mmap_size=8388608;")

    @classmethod
    def tearDownClass(cls):
        cls.db.close()

    def test_integrity_and_coverage(self):
        self.assertEqual(self.db.execute("PRAGMA integrity_check").fetchone()[0], "ok")
        self.assertGreater(self.db.execute("SELECT count(*) FROM entries").fetchone()[0], 850_000)
        for word in ["众筹", "短视频", "人工智能", "二维码", "自媒体", "拼团"]:
            with self.subTest(word=word):
                self.assertIsNotNone(self.db.execute("SELECT 1 FROM entries WHERE text=? LIMIT 1", (word,)).fetchone())

    def test_exact_and_untoned_lookup(self):
        for tones in [("4", "2"), (None, None)]:
            sql, args = query(self.db, ["ㄓㄨㄥ", "ㄔㄡ"], tones)
            self.assertEqual(self.db.execute(sql, args).fetchone()[:2], ("众筹", "ㄓㄨㄥ4 ㄔㄡ2"))

    def test_completion_is_bounded_and_indexed(self):
        sql, args = query(self.db, ["ㄓㄨㄥ", "ㄔ"], ["4", None], True)
        self.assertIn("众筹", [row[0] for row in self.db.execute(sql, args)])
        plan = str(self.db.execute("EXPLAIN QUERY PLAN " + sql, args).fetchall())
        self.assertIn("SEARCH entries USING INDEX lookup", plan)
        self.assertNotIn("SCAN entries", plan)

    def test_partial_selection_keeps_remaining_character_available(self):
        for sound, tone, expected in [("ㄓㄨㄥ", "4", "众"), ("ㄔㄡ", "2", "筹")]:
            sql, args = query(self.db, [sound], [tone])
            self.assertIn(expected, [row[0] for row in self.db.execute(sql, args)])

    def test_wrong_known_tone_is_filtered(self):
        sql, args = query(self.db, ["ㄓㄨㄥ", "ㄔㄡ"], ["1", "2"])
        self.assertNotIn("众筹", [row[0] for row in self.db.execute(sql, args)])

    def test_ascii_sound_encoding_and_read_only_open(self):
        self.assertEqual(encode_sound_key(["ㄓㄨㄥ", "ㄔㄡ"]), "Oda P]")
        self.assertEqual(to_zhuyin("zhong"), "ㄓㄨㄥ")
        self.assertEqual(to_zhuyin("wong"), "ㄨㄥ")
        with self.assertRaises(sqlite3.OperationalError):
            self.db.execute("DELETE FROM entries WHERE rank=-1")

    def test_character_coverage_and_neutral_tone_ye(self):
        count = self.db.execute("SELECT count(DISTINCT text) FROM entries WHERE syllables=1").fetchone()[0]
        self.assertGreaterEqual(count, 44_269)
        for char in ["吔", "㖏", "㙍", "乾"]:
            with self.subTest(character=char):
                self.assertIsNotNone(self.db.execute("SELECT 1 FROM entries WHERE syllables=1 AND text=? LIMIT 1", (char,)).fetchone())
        sql, args = query(self.db, ["ㄧㄝ"], ["5"])
        self.assertIn("吔", [row[0] for row in self.db.execute(sql, args)])

    def test_compiler_creates_closed_reopenable_database(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "sample.sqlite"
            write_database({("众筹", "ㄓㄨㄥ0 ㄔㄡ2"): 100}, path)
            with closing(sqlite3.connect(path)) as db:
                sql, args = query(db, ["ㄓㄨㄥ", "ㄔㄡ"], ["4", "2"])
                self.assertEqual(db.execute(sql, args).fetchone()[0], "众筹")


def benchmark():
    db = sqlite3.connect(DATABASE.as_uri() + "?mode=ro", uri=True)
    db.executescript("PRAGMA cache_size=-512; PRAGMA mmap_size=8388608;")
    cases = [(["ㄓㄨㄥ", "ㄔㄡ"], [None, None], False),
             (["ㄕ"], [None], True), (["ㄓㄨㄥ", "ㄔ"], [None, None], True),
             (["ㄖㄣ", "ㄍㄨㄥ", "ㄓ", "ㄋㄥ"], [None] * 4, False)]
    samples = []
    for _ in range(100):
        for sounds, tones, completion in cases:
            sql, args = query(db, sounds, tones, completion)
            started = time.perf_counter()
            db.execute(sql, args).fetchall()
            samples.append((time.perf_counter() - started) * 1000)
    db.close()
    print(f"Host SQLite lookup only: median={statistics.median(samples):.3f}ms; p95={sorted(samples)[int(len(samples)*.95)]:.3f}ms; max={max(samples):.3f}ms")


if __name__ == "__main__":
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(DictionaryTests))
    if not result.wasSuccessful():
        raise SystemExit(1)
    benchmark()
