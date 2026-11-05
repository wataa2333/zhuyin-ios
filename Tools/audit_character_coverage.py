"""Audit character and reading coverage against the pinned source dictionaries."""
import argparse
import json
import sqlite3
import unicodedata
from pathlib import Path

from build_lexicon import load_character_tones, load_simplification, encode_reading, split_tone, to_zhuyin, CHARACTER_READINGS


def audit(database, pinyin_data, opencc, standard_table):
    tones = load_character_tones(pinyin_data)
    simplification = load_simplification(opencc)
    expected = set()
    for (original, sound), readings in tones.items():
        if original != "〇" and not unicodedata.name(original, "").startswith("CJK UNIFIED IDEOGRAPH"):
            continue
        for char in {original, original.translate(simplification)}:
            expected.update((char, sound + tone) for tone in readings)
    expected.update((char, encode_reading(reading)) for char, reading in CHARACTER_READINGS.items())
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as db:
        actual = set(db.execute("SELECT text,reading FROM entries WHERE syllables=1"))
    db.close()
    actual_chars = {c for c, _ in actual}
    source_characters = set()
    unsupported = []
    for line in pinyin_data.read_text(encoding="utf-8").splitlines():
        if not line.startswith("U+"):
            continue
        code, readings = line.partition("#")[0].split(": ", 1)
        char = chr(int(code[2:], 16))
        if char != "〇" and not unicodedata.name(char, "").startswith("CJK UNIFIED IDEOGRAPH"):
            continue
        source_characters.add(char)
        for reading in readings.strip().split(","):
            sound, _ = split_tone(reading)
            if not to_zhuyin(sound):
                unsupported.append(dict(character=char, pinyin=reading))
    # The upstream table has a separate extensions section before the actual 8105-character list.
    body = standard_table.read_text(encoding="utf-8").split("### 字表", 1)[1]
    standard = {line.split("\t")[0] for line in body.splitlines()
                if not line.startswith("#") and len(line.split("\t")[0]) == 1}
    report = {
        "standard_reference": "Rime Ice 8105.dict.yaml, section 字表; includes upstream supplemental forms, so this is not exactly the official 8105-character set",
        "standard_characters": len(standard),
        "missing_standard_characters": sorted(standard - actual_chars),
        "pinyin_reference_characters": len({c for c, _ in expected}),
        "pinyin_reference_readings": len(expected),
        "missing_pinyin_characters": sorted({c for c, _ in expected} - actual_chars),
        "missing_pinyin_readings": [dict(character=c, reading=r) for c, r in sorted(expected - actual)],
        "available_characters": len(actual_chars),
        "available_readings": len(actual),
        "pinyin_source_characters": len(source_characters),
        "source_characters_without_any_candidate": sorted(source_characters - actual_chars),
        "unsupported_source_readings": unsupported,
        "scope": "Convertible Mandarin readings in the pinned pinyin-data dataset plus the 8105 reference. This does not claim coverage of every Unicode Han character or every dialect reading."
    }
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("pinyin_data", type=Path)
    parser.add_argument("opencc", type=Path)
    parser.add_argument("standard_table", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.database, args.pinyin_data, args.opencc, args.standard_table)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: len(v) if isinstance(v, list) else v for k, v in report.items()}, ensure_ascii=True))
