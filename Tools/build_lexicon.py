"""Convert the source dictionaries listed in README.md into the bundled TSV."""

import argparse
from collections import defaultdict
from pathlib import Path
import sqlite3
import unicodedata


INITIALS = dict(zip(
    "b p m f d t n l g k h j q x zh ch sh r z c s".split(),
    "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ",
))
FINALS = {
    "": "", "a": "ㄚ", "o": "ㄛ", "e": "ㄜ", "ê": "ㄝ",
    "ai": "ㄞ", "ei": "ㄟ", "ao": "ㄠ", "ou": "ㄡ",
    "an": "ㄢ", "en": "ㄣ", "ang": "ㄤ", "eng": "ㄥ", "er": "ㄦ",
    "i": "ㄧ", "ia": "ㄧㄚ", "io": "ㄧㄛ", "ie": "ㄧㄝ",
    "iai": "ㄧㄞ", "iao": "ㄧㄠ", "iu": "ㄧㄡ", "iou": "ㄧㄡ", "ian": "ㄧㄢ",
    "in": "ㄧㄣ", "iang": "ㄧㄤ", "ing": "ㄧㄥ", "iong": "ㄩㄥ",
    "u": "ㄨ", "ua": "ㄨㄚ", "uo": "ㄨㄛ", "uai": "ㄨㄞ",
    "ui": "ㄨㄟ", "uei": "ㄨㄟ", "uan": "ㄨㄢ", "un": "ㄨㄣ", "uen": "ㄨㄣ", "uang": "ㄨㄤ",
    "ong": "ㄨㄥ", "ueng": "ㄨㄥ",
    "ü": "ㄩ", "üe": "ㄩㄝ", "üan": "ㄩㄢ", "ün": "ㄩㄣ",
}
TONES = dict(zip("\u0304\u0301\u030c\u0300", "1234"))

# Word readings where character-by-character inference would miss common usage.
WORD_READINGS = {
    "你好": "nǐ hǎo", "你们": "nǐ men", "我们": "wǒ men",
    "什么": "shén me", "怎么": "zěn me", "这个": "zhè ge", "那个": "nà ge",
    "朋友": "péng you", "谢谢": "xiè xie", "对不起": "duì bu qǐ",
    "没关系": "méi guān xi", "再见": "zài jiàn", "中国": "zhōng guó",
    "中国人": "zhōng guó rén", "中华人民共和国": "zhōng huá rén mín gòng hé guó",
    "简体": "jiǎn tǐ", "简体中文": "jiǎn tǐ zhōng wén",
    "注音": "zhù yīn", "注音输入法": "zhù yīn shū rù fǎ",
    "输入法": "shū rù fǎ", "电脑": "diàn nǎo", "软件": "ruǎn jiàn",
    "众筹": "zhòng chóu",
    "音乐": "yīn yuè", "快乐": "kuài lè", "银行": "yín háng",
    "长大": "zhǎng dà", "重庆": "chóng qìng",
    "有什么": "yǒu shén me", "没什么": "méi shén me",
    "想什么": "xiǎng shén me", "说什么": "shuō shén me",
    "要什么": "yào shén me", "在干什么": "zài gàn shén me",
    "你在干嘛": "nǐ zài gàn má", "什么情况": "shén me qíng kuàng",
    "有时间": "yǒu shí jiān", "没时间": "méi shí jiān",
    "为什么呢": "wèi shén me ne", "怎么了": "zěn me le",
    "等一下": "děng yí xià", "不用谢": "bú yòng xiè",
    "没问题": "méi wèn tí", "没办法": "méi bàn fǎ",
    "在哪里": "zài nǎ lǐ", "好不好": "hǎo bu hǎo",
    "觉得": "jué de", "漂亮": "piào liang",
    "时候": "shí hou", "知道": "zhī dao", "东西": "dōng xi",
    "喜欢": "xǐ huan", "意思": "yì si", "认识": "rèn shi",
    "明白": "míng bai", "麻烦": "má fan", "舒服": "shū fu",
    "什么意思": "shén me yì si",
    "有空吗": "yǒu kòng ma", "方便吗": "fāng biàn ma", "你忙吗": "nǐ máng ma",
    "你吃饭了吗": "nǐ chī fàn le ma", "最近怎么样": "zuì jìn zěn me yàng",
    "我到了": "wǒ dào le", "我在路上": "wǒ zài lù shang", "我马上到": "wǒ mǎ shàng dào",
    "等我一下": "děng wǒ yí xià", "先这样": "xiān zhè yàng", "晚点聊": "wǎn diǎn liáo",
    "回头再说": "huí tóu zài shuō", "发给我": "fā gěi wǒ", "再说一遍": "zài shuō yí biàn",
    "你说得对": "nǐ shuō de duì", "没关系的": "méi guān xi de", "真的假的": "zhēn de jiǎ de",
    "我知道了": "wǒ zhī dao le", "知道了": "zhī dao le", "谢谢你": "xiè xie nǐ",
    "我没听清": "wǒ méi tīng qīng", "你方便的时候": "nǐ fāng biàn de shí hou",
    "稍等一下": "shāo děng yí xià", "有点问题": "yǒu diǎn wèn tí",
}

# Readings that only came from assigning each character its first listed tone.
REJECTED_READINGS = {
    "觉得": "jué dé",
    "漂亮": "piāo liàng",
}


def split_tone(pinyin):
    base = []
    tone = "5"
    for character in unicodedata.normalize("NFD", pinyin):
        if character in TONES:
            tone = TONES[character]
        else:
            base.append(character)
    return unicodedata.normalize("NFC", "".join(base)), tone


def to_zhuyin(pinyin):
    pinyin = pinyin.replace("v", "ü").replace("u:", "ü")
    if pinyin.startswith("y"):
        final = pinyin[1:]
        if final.startswith("u"):
            final = "ü" + final[1:]
        elif final == "ong":
            final = "iong"
        elif not final.startswith("i"):
            final = "i" + final
        return FINALS.get(final)
    if pinyin.startswith("w"):
        final = pinyin[1:]
        return FINALS.get(final if final.startswith("u") else "u" + final)

    initial = next((prefix for prefix in (pinyin[:2], pinyin[:1]) if prefix in INITIALS), "")
    final = pinyin[len(initial):]
    if initial in ("zh", "ch", "sh", "r", "z", "c", "s") and final == "i":
        final = ""
    if initial in ("j", "q", "x", "n", "l") and (
        final == "ue" or (initial in ("j", "q", "x") and final.startswith("u"))
    ):
        final = "ü" + final[1:]
    if final not in FINALS:
        return None
    return INITIALS.get(initial, "") + FINALS[final]


def load_character_tones(path):
    tones = defaultdict(list)
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("U+"):
            continue
        code, readings = line.split("#", 1)[0].split(": ", 1)
        character = chr(int(code[2:], 16))
        for reading in readings.strip().split(","):
            base, tone = split_tone(reading)
            symbols = to_zhuyin(base)
            if symbols:
                tones[(character, symbols)].append(tone)
    return tones


def load_simplification(path):
    mapping = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if line and not line.startswith("#"):
            traditional, variants = line.split("\t", 1)
            mapping[ord(traditional)] = variants.split()[0]
    return mapping


def weighted_rows(path):
    with path.open(encoding="utf-8") as source:
        for line in source:
            if line.startswith("#"):
                continue
            columns = line.rstrip().split("\t")
            if len(columns) == 2:
                columns.append("100")
            if len(columns) == 3 and columns[2].isdigit():
                text, pinyin, weight = columns
                yield text, pinyin, int(weight)


def load_phrase_tones(path):
    readings = defaultdict(set)
    with path.open(encoding="utf-8") as source:
        for line in source:
            text, _, pinyin = line.partition("#")[0].strip().partition(": ")
            pairs = [(to_zhuyin(base), tone) for base, tone in map(split_tone, pinyin.split())]
            if len(text) > 1 and len(pairs) == len(text) and all(sound for sound, _ in pairs):
                sounds, tones = zip(*pairs)
                readings[(text, sounds)].add(tones)
    return readings


def build(rime, pinyin_data, opencc, ice, phrase_data, extra_ice=()):
    tones = load_character_tones(pinyin_data)
    simplified = load_simplification(opencc)
    phrase_tones = load_phrase_tones(phrase_data)
    entries = {}

    # Keep the established character coverage and order for single-character input.
    for original, pinyin, weight in weighted_rows(rime):
        if len(original) != 1:
            continue
        text = original.translate(simplified)
        sound = to_zhuyin(pinyin)
        if not sound:
            continue
        for tone in tones.get((original, sound)) or tones.get((text, sound)) or ["0"]:
            key = (text, sound + tone)
            entries[key] = max(weight, entries.get(key, 0))

    # Merge all enabled tables. Query-time indexing replaces the former 65,000-reading cutoff.
    phrases = sorted(
        (row for path in (ice, *extra_ice) for row in weighted_rows(path) if len(row[0]) > 1),
        key=lambda row: (-row[2], row[0], row[1]),
    )
    rejected = {(text, encode_reading(pinyin)) for text, pinyin in REJECTED_READINGS.items()}
    curated = {(text, encode_reading(pinyin)): 1_000_000_000 for text, pinyin in WORD_READINGS.items()}
    entries.update(curated)
    for text, pinyin, weight in phrases:
        if not all(c == "〇" or unicodedata.name(c, "").startswith("CJK UNIFIED IDEOGRAPH") for c in text):
            continue
        sounds = tuple(to_zhuyin(syllable) for syllable in pinyin.split())
        if len(sounds) != len(text) or not all(sounds):
            continue
        readings = phrase_tones.get((text, sounds))
        if not readings:
            # Do not assert a guessed tone when the same sound has multiple character tones.
            # Tone zero is matched as unspecified by the runtime, preserving explicit-tone lookup.
            def inferred_tone(char, sound):
                known = set(tones.get((char, sound), []))
                return next(iter(known)) if len(known) == 1 else "0"
            readings = [tuple(inferred_tone(char, sound) for char, sound in zip(text, sounds))]
        for reading in sorted(readings):
            key = (text, " ".join(sound + tone for sound, tone in zip(sounds, reading)))
            if key not in entries and key not in rejected:
                entries[key] = weight

    return entries


def encode_reading(pinyin):
    return " ".join(to_zhuyin(base) + tone for base, tone in map(split_tone, pinyin.split()))


def encode_sound_key(sounds):
    # One ASCII byte per Zhuyin symbol; preserves prefix lookup without duplicating UTF-8 text.
    return " ".join("".join(chr(ord(symbol) - 0x3105 + 65) for symbol in sound) for sound in sounds)


def write_database(entries, output):
    """Compile an immutable SQLite dictionary; the iOS keyboard only opens it read-only."""
    ranked = sorted(entries, key=lambda entry: (-entries[entry], *entry))
    temporary = output.with_suffix(".building")
    if temporary.exists():
        temporary.unlink()
    with sqlite3.connect(temporary) as db:
        db.executescript("""
            PRAGMA page_size=4096;
            PRAGMA journal_mode=OFF;
            PRAGMA synchronous=OFF;
            PRAGMA user_version=1;
            CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
            CREATE TABLE entries(
                rank INTEGER PRIMARY KEY,
                syllables INTEGER NOT NULL,
                sound_key TEXT NOT NULL,
                text TEXT NOT NULL,
                reading TEXT NOT NULL
            );
        """)
        db.executemany("INSERT INTO metadata VALUES (?, ?)", [
            ("format", "zhuyin-sqlite-1"),
            ("entry_count", str(len(ranked))),
            ("sources", "rime-pinyin-simp; rime-ice base/ext/tencent/others; phrase-pinyin-data; pinyin-data"),
        ])
        def rows():
            for rank, (text, reading) in enumerate(ranked):
                sounds = encode_sound_key(syllable[:-1] for syllable in reading.split())
                yield rank, len(reading.split()), sounds, text, reading
        db.executemany("INSERT INTO entries VALUES (?, ?, ?, ?, ?)", rows())
        db.execute("CREATE INDEX lookup ON entries(syllables, sound_key, rank)")
        db.execute("ANALYZE")
        assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    db.close()
    temporary.replace(output)
    print(f"Wrote {len(ranked):,} readings to {output.name} ({output.stat().st_size:,} bytes)", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rime", type=Path, help="pinyin_simp.dict.yaml")
    parser.add_argument("pinyin_data", type=Path, help="pinyin.txt")
    parser.add_argument("opencc", type=Path, help="TSCharacters.txt")
    parser.add_argument("ice", type=Path, help="Rime Ice cn_dicts/base.dict.yaml")
    parser.add_argument("phrase_data", type=Path, help="phrase-pinyin-data pinyin.txt")
    parser.add_argument("--extra-ice", type=Path, nargs="*", default=[], help="Rime Ice ext/tencent/others tables")
    parser.add_argument("--output", type=Path, help="Output .sqlite path (default: Keyboard/Lexicon.sqlite)")
    args = parser.parse_args()
    output = args.output or Path(__file__).resolve().parents[1] / "Keyboard" / "Lexicon.sqlite"
    entries = build(args.rime, args.pinyin_data, args.opencc, args.ice, args.phrase_data, args.extra_ice)
    write_database(entries, output)


if __name__ == "__main__":
    main()
