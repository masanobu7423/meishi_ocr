import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';

const _a = '''---
type: meishi
name: 山田 太郎
company: 株式会社サンライズ
job: 営業
pref: 東京都
scanned: 2026-10-24
tags: [名刺, 会社_サンライズ]
---
# 山田 太郎
''';
const _b = '''---
type: meishi
name: 佐々木 健
company: 株式会社サンライズ
job: 経営
pref: 東京都
scanned: 2026-10-25
tags: [名刺]
---
''';
const _c = '''---
type: meishi
name: 鈴木 一郎
company: トビショク商事
pref: 大阪府
scanned: 2026-10-25
tags: [名刺]
---
''';

const _d = '''---
type: meishi
name: 高橋 二郎
company: 高橋工務店
category: 協力会社
related: 鈴木, 佐藤
scanned: 2026-10-26
tags: [名刺]
---
''';

void main() {
  test('buildIndex groups by 区分 and by each related user', () {
    final md = buildIndex({'高橋_二郎_2026-10-26': _d, '鈴木_一郎_2026-10-25': _c});
    expect(md, contains('## 区分別\n\n- [[区分_協力会社]] (1): [[高橋_二郎_2026-10-26|高橋 二郎]]\n- 未分類 (1): [[鈴木_一郎_2026-10-25|鈴木 一郎]]\n'));
    expect(md, contains('## 関係者別\n\n'));
    expect(md, contains('- [[鈴木]] (1): [[高橋_二郎_2026-10-26|高橋 二郎]]\n'));
    expect(md, contains('- [[佐藤]] (1): [[高橋_二郎_2026-10-26|高橋 二郎]]\n'));
  });

  test('parseFrontmatter reads the flat key: value block only', () {
    final fm = parseFrontmatter(_a);
    expect(fm['name'], '山田 太郎');
    expect(fm['tags'], '[名刺, 会社_サンライズ]');
    expect(fm.containsKey('# 山田 太郎'), isFalse);
    expect(parseFrontmatter('no frontmatter'), isEmpty);
  });

  test('buildIndex lists every card and groups by company, job and pref', () {
    final md = buildIndex({
      '山田_太郎_2026-10-24': _a,
      '佐々木_健_2026-10-25': _b,
      '鈴木_一郎_2026-10-25': _c,
    });
    expect(md, startsWith('---\ntype: meishi_index\ncount: 3\n'));
    expect(md, contains('| [[佐々木_健_2026-10-25|佐々木 健]] | [[株式会社サンライズ]] | 経営 | — | 東京都 | 2026-10-25 |'));
    expect(md, contains('## 会社別\n\n- [[株式会社サンライズ]] (2): [[山田_太郎_2026-10-24|山田 太郎]], [[佐々木_健_2026-10-25|佐々木 健]]\n- [[トビショク商事]] (1)'));
    expect(md, contains('## 職種別\n\n- [[職種_営業]] (1)'));
    expect(md, contains('- 未分類 (1): [[鈴木_一郎_2026-10-25|鈴木 一郎]]'));
    expect(md, contains('## 地域別\n\n- [[東京都]] (2)'));
    expect(md, contains('#名刺_索引'));
  });
}
