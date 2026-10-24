// Romaji helpers for names printed in Latin letters.

/// ML Kit splits words on photos ("Takahash i", "Taka hashi"). A name token
/// never starts lowercase, so a lowercase fragment belongs to the word before it.
String fixRomanSpacing(String s) =>
    s.replaceAllMapped(RegExp(r'([A-Za-z]{2,}) ([a-z]+)\b'), (m) => '${m[1]}${m[2]}');

const _vowels = 'aiueo';
const _kana = <String, String>{
  'a': 'ア', 'i': 'イ', 'u': 'ウ', 'e': 'エ', 'o': 'オ',
  'ka': 'カ', 'ki': 'キ', 'ku': 'ク', 'ke': 'ケ', 'ko': 'コ',
  'sa': 'サ', 'shi': 'シ', 'si': 'シ', 'su': 'ス', 'se': 'セ', 'so': 'ソ',
  'ta': 'タ', 'chi': 'チ', 'ti': 'チ', 'tsu': 'ツ', 'tu': 'ツ', 'te': 'テ', 'to': 'ト',
  'na': 'ナ', 'ni': 'ニ', 'nu': 'ヌ', 'ne': 'ネ', 'no': 'ノ',
  'ha': 'ハ', 'hi': 'ヒ', 'fu': 'フ', 'hu': 'フ', 'he': 'ヘ', 'ho': 'ホ',
  'ma': 'マ', 'mi': 'ミ', 'mu': 'ム', 'me': 'メ', 'mo': 'モ',
  'ya': 'ヤ', 'yu': 'ユ', 'yo': 'ヨ',
  'ra': 'ラ', 'ri': 'リ', 'ru': 'ル', 're': 'レ', 'ro': 'ロ',
  'wa': 'ワ', 'wo': 'ヲ', 'wi': 'ウィ', 'we': 'ウェ', 'n': 'ン',
  'ga': 'ガ', 'gi': 'ギ', 'gu': 'グ', 'ge': 'ゲ', 'go': 'ゴ',
  'za': 'ザ', 'ji': 'ジ', 'zi': 'ジ', 'zu': 'ズ', 'ze': 'ゼ', 'zo': 'ゾ',
  'da': 'ダ', 'de': 'デ', 'do': 'ド',
  'ba': 'バ', 'bi': 'ビ', 'bu': 'ブ', 'be': 'ベ', 'bo': 'ボ',
  'pa': 'パ', 'pi': 'ピ', 'pu': 'プ', 'pe': 'ペ', 'po': 'ポ',
  'kya': 'キャ', 'kyu': 'キュ', 'kyo': 'キョ',
  'sha': 'シャ', 'shu': 'シュ', 'sho': 'ショ', 'she': 'シェ',
  'sya': 'シャ', 'syu': 'シュ', 'syo': 'ショ',
  'cha': 'チャ', 'chu': 'チュ', 'cho': 'チョ', 'che': 'チェ',
  'tya': 'チャ', 'tyu': 'チュ', 'tyo': 'チョ',
  'nya': 'ニャ', 'nyu': 'ニュ', 'nyo': 'ニョ',
  'hya': 'ヒャ', 'hyu': 'ヒュ', 'hyo': 'ヒョ',
  'mya': 'ミャ', 'myu': 'ミュ', 'myo': 'ミョ',
  'rya': 'リャ', 'ryu': 'リュ', 'ryo': 'リョ',
  'gya': 'ギャ', 'gyu': 'ギュ', 'gyo': 'ギョ',
  'ja': 'ジャ', 'ju': 'ジュ', 'jo': 'ジョ', 'je': 'ジェ',
  'zya': 'ジャ', 'zyu': 'ジュ', 'zyo': 'ジョ',
  'bya': 'ビャ', 'byu': 'ビュ', 'byo': 'ビョ',
  'pya': 'ピャ', 'pyu': 'ピュ', 'pyo': 'ピョ',
  'fa': 'ファ', 'fi': 'フィ', 'fe': 'フェ', 'fo': 'フォ', 'ye': 'イェ',
};

/// Hepburn (and common kunrei) romaji -> katakana for one word.
/// Returns null when a syllable cannot be converted (not a Japanese name).
/// ponytail: no long-vowel guessing ("Taro" stays タロ); contacts sort fine.
String? romanToKana(String word) {
  var s = word
      .toLowerCase()
      .replaceAll('ō', 'ou')
      .replaceAll('ū', 'uu')
      .replaceAll('ā', 'aa')
      .replaceAll('ē', 'ee')
      .replaceAll('ī', 'ii')
      .replaceAll("'", '')
      .replaceAll('-', '');
  // "Itoh"/"Ohno": h after o with no vowel following marks a long vowel.
  s = s.replaceAllMapped(RegExp(r'oh(?![aiueo])'), (m) => 'ou');
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (!RegExp(r'[a-z]').hasMatch(c)) return null;
    // syllabic n: before a consonant (not y) or at the end
    if (c == 'n' && (i + 1 == s.length || !'${_vowels}y'.contains(s[i + 1]))) {
      out.write('ン');
      i++;
      continue;
    }
    // sokuon: doubled consonant (tt, kk, ss, pp, cch -> tch)
    if (i + 1 < s.length && !_vowels.contains(c) && c != 'n' &&
        (s[i + 1] == c || (c == 't' && s.startsWith('ch', i + 1)))) {
      out.write('ッ');
      i++;
      continue;
    }
    String? hit;
    for (var len = 3; len >= 1; len--) {
      if (i + len <= s.length && _kana.containsKey(s.substring(i, i + len))) {
        hit = s.substring(i, i + len);
        break;
      }
    }
    if (hit == null) return null;
    out.write(_kana[hit]);
    i += hit.length;
  }
  return out.toString();
}

/// Katakana reading in Japanese order (family given) from a printed romaji
/// name. "SUZUKI Ichiro" keeps order (caps = family); "Taro Yamada" flips.
String? kanaName(String roman) {
  final tokens = fixRomanSpacing(roman).trim().split(RegExp(r'\s+'));
  final ordered = tokens.length == 2 && tokens[0] != tokens[0].toUpperCase()
      ? [tokens[1], tokens[0]]
      : tokens;
  final kana = ordered.map(romanToKana).toList();
  return kana.contains(null) ? null : kana.join(' ');
}
