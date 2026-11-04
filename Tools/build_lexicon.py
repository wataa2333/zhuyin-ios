"""Convert the source dictionaries listed in README.md into the bundled TSV."""

import argparse
from collections import defaultdict
from pathlib import Path
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
PHRASE_LIMIT = 65_000

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


def build(rime, pinyin_data, opencc, ice, phrase_data):
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

    # Use the most frequent simplified phrases from Rime Ice within the keyboard's size budget.
    phrases = sorted(
        (row for row in weighted_rows(ice) if len(row[0]) > 1),
        key=lambda row: (-row[2], row[0], row[1]),
    )
    rejected = {(text, encode_reading(pinyin)) for text, pinyin in REJECTED_READINGS.items()}
    added = 0
    for text, pinyin, weight in phrases:
        if not all(c == "〇" or unicodedata.name(c, "").startswith("CJK UNIFIED IDEOGRAPH") for c in text):
            continue
        sounds = tuple(to_zhuyin(syllable) for syllable in pinyin.split())
        if len(sounds) != len(text) or not all(sounds):
            continue
        readings = phrase_tones.get((text, sounds))
        if not readings:
            readings = [tuple(tones.get((char, sound), ["0"])[0] for char, sound in zip(text, sounds))]
        for reading in sorted(readings):
            key = (text, " ".join(sound + tone for sound, tone in zip(sounds, reading)))
            if key not in entries and key not in rejected:
                entries[key] = weight
                added += 1
                if added == PHRASE_LIMIT:
                    break
        if added == PHRASE_LIMIT:
            break

    for text, pinyin in WORD_READINGS.items():
        reading = encode_reading(pinyin)
        entries[(text, reading)] = 1_000_000_000
    return entries


def encode_reading(pinyin):
    return " ".join(to_zhuyin(base) + tone for base, tone in map(split_tone, pinyin.split()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rime", type=Path, help="pinyin_simp.dict.yaml")
    parser.add_argument("pinyin_data", type=Path, help="pinyin.txt")
    parser.add_argument("opencc", type=Path, help="TSCharacters.txt")
    parser.add_argument("ice", type=Path, help="Rime Ice cn_dicts/base.dict.yaml")
    parser.add_argument("phrase_data", type=Path, help="phrase-pinyin-data pinyin.txt")
    args = parser.parse_args()
    output = Path(__file__).resolve().parents[1] / "Keyboard" / "Lexicon.tsv"
    entries = build(args.rime, args.pinyin_data, args.opencc, args.ice, args.phrase_data)
    ranked = sorted(entries, key=lambda entry: (-entries[entry], *entry))
    with output.open("w", encoding="utf-8", newline="\n") as dictionary:
        for text, reading in ranked:
            dictionary.write(f"{text}\t{reading}\n")
    print(f"Wrote {len(ranked):,} readings to {output.name}")


if __name__ == "__main__":
    main()
