# DESIGN.md — 名刺スキャン (meishi_ocr)

Owner decisions about how this app looks and talks. Code consumes these values and never redefines them. Claude reads this file before any UI work (harness:designing-ui). Keep it under 150 lines; CLAUDE.md only points here.

## 1. Who and why

- Audience: 展示会や商談で名刺を受け取る個人・小規模事業者。1 日に 1〜30 枚。片手で、机の上で、急いで使う。
- Primary job of the UI, one sentence: 撮った名刺を確認して、電話帳に入れる。それ以外は邪魔をしない。
- Tone, three adjectives and one you reject: 速い・静か・正直。拒否: にぎやか（装飾、効果音、祝福アニメーション）。
- The one memorable element (everything else stays quiet): 読み取った名刺の写真が画面上部に残り、その下の項目を「写真を見ながら」直せること。読み取った文字はチップとして並び、タップで今触っている項目に入る。

TODO(owner): 上の 4 点は Claude の仮決め（2026-10-25）。違えば書き換える。

## 2. Tokens

Source of truth in code: `lib/theme.dart`. A value not in this table does not appear in UI code. New token → add a row here and in the theme file in the same commit.

| token | value | defined in |
|---|---|---|
| primary | ColorScheme.fromSeed(seed 0xFF1D9E75, bright teal) → `colorScheme.primary` | lib/theme.dart |
| surface / background | white (`colorScheme.surface`); grouping tints = pale teal `surfaceContainerLow…Highest` / `primaryContainer`（件数タイル、選択行、ナビの指示）| lib/theme.dart |
| shapes | ボタン・チップ・セグメントはピル（999）、カード・行は `AppRadius.medium` 16、ダイアログ・件数タイルは `AppRadius.large` 20。罫線は `outlineVariant`（淡いティール） | lib/theme.dart |
| depth | 立体: 主ボタン elevation 3、輪郭ボタン・行カード elevation 2、件数タイルは `appShadow`（ティール 18 % のぼかし 14 / 下 5）。影の色は常に primary 系、黒い影は使わない | lib/theme.dart |
| on-surface (text) | `colorScheme.onSurface` | lib/theme.dart |
| error / warning / success | `colorScheme.error` / `tertiary` / `primary` | lib/theme.dart |
| display font | system default (Noto Sans JP on Android) | — |
| body font | system default | — |
| type scale | Material 3 textTheme: titleLarge / titleMedium / bodyLarge / labelMedium | lib/theme.dart |
| radius (small / medium / large) | 10 / 16 / 20 (`AppRadius`) | lib/theme.dart |
| spacing unit | 8 (`AppSpace.unit`); gutters 16 | lib/theme.dart |
| sizes (icon-small / thumb / hero) | 18 / 96 / 64 (`AppSize`) | lib/theme.dart |
| motion duration | none of our own; Material defaults only, on user action | — |

2026-10-25: 案 A「ホワイト＆ティール」を採用（白地 + 淡いティールの面 + ピル型）。ブランド色が決まれば seed だけ差し替える。

## 2b. Structure

- 下部タブ 4 つ（ホーム / スキャン / 検索 / 一覧）、`NavigationBar`。タブ間で状態を保つため `IndexedStack`。
- ホームは「件数 2 つ → 未確認 / 未登録 / 連絡予定（期限切れ + 7 日以内、0 件なら非表示）/ 重複（0 件なら非表示）（タップで一覧をその絞り込みで開く）→ 主要操作 3 つ → 最近の 5 枚」の順。他タブで名刺を選ぶとスキャンタブに開く。電話帳と紐付いた名刺には写真の下に「電話帳の内容を取り込む」（TextButton）。
- 一覧の行は日付の下に状態（未確認 = error 色、未登録 = tertiary 色）。登録済は何も出さない（静かに）。一覧上部に「すべて / 未確認 / 未登録 / 重複 / 連絡予定」の `SegmentedButton`。行の右に「期限切れ MM/DD」（errorContainer）/「連絡 MM/DD」（tertiaryContainer）のピル。
- 一覧・検索・最近の名刺は長押しで選択モード（行の先頭が `Checkbox` に替わる）。上部のバーに「N 件を選択中 / すべて選択 / 修正（1 件のとき）/ 共有 / 削除（error 色）/ 選択解除」。削除は件数を示す確認ダイアログを挟む。
- 右上メニューは全タブ共通（登録先アカウント、未登録をまとめて登録、電話帳から取り込む、職種の一覧を編集、全件を vCard で共有、vCard 書き出し、全件を CSV で共有、バックアップを共有、バックアップを作る、バックアップから復元）。共有は端末の共有シートに任せ、アプリ内に送信先の UI は作らない。スキャンタブだけ「まとめて取込」アイコンが付く。

## 3. Components and states

- Button roles → widget: primary = `FilledButton`（電話帳に登録）, secondary = `OutlinedButton` / `FilledButton.tonal`（保存、撮影）, tertiary = `TextButton`（画面内の補助操作: すべて見る、電話帳の内容を取り込む、選択バーの項目）, destructive = `IconButton` in `colorScheme.error`（保存済みなら「この名刺を削除」、未保存の読み取りなら「この読み取りを破棄」）。
- Choice fields: `DropdownMenu`（区分は固定 8 択 + 入力可、職種は利用者の一覧（既定は建設業種 29 件、メニュー「職種の一覧を編集」で追加・名前変更・削除）+ 使用中の値 + 入力可、都道府県は 47 件）。信頼度は 1〜5 の `SegmentedButton`（もう一度押すと解除）。次回連絡日は読み取り専用 `TextField` + 端末の `showDatePicker`、× で消す。検索タブは文字入力の下に職種の `FilterChip`（使用中の値のみ）と信頼度下限の `SegmentedButton`、右端に件数。複数値の項目（関係者・資格）はカンマ区切りの `TextField` に、過去に使った値を `InputChip` で並べてタップで追記。住所は全文の `TextField` を正とし、`ExpansionTile`「住所の内訳」で 6 区分に分けて直せる（双方向同期）。
- Every async view renders: loading（OCR 中はスピナーと「読み取り中…」、保存/登録ボタンは無効）, empty（撮影・アルバム・続けて撮影への誘導）, error（何が起きたか + 次に何をするか、上部バナー）, success（SnackBar「電話帳に登録しました」）
- Irreversible actions: 電話帳への登録は取り消せないので、重複候補があるときは左右比較の画面（統合 / 別人として登録 / 既存を電話帳アプリで編集 / 既存を削除して登録）。削除だけは確認ダイアログを挟む。名刺の削除（読み取り結果と写真）と、バックアップからの復元（同じ名刺を上書き）も確認ダイアログ。それ以外は確認なし。

## 4. Accessibility floor (non-negotiable)

- Contrast: body text ≥ 4.5:1, large text ≥ 3:1（M3 の onSurface/surface はこれを満たす）
- Targets: ≥ 48dp（IconButton 既定、チップは minimum 48 高さ）
- Every icon and image: a label（`tooltip` / `Semantics`）, or explicitly decorative
- Reduced motion honored（`MediaQuery.disableAnimations` で進捗以外のアニメーションを止める）
- Text scales to 200% without clipping（固定高さの Row を使わない、Wrap と Expanded）

## 5. Motion

- Allowed: 操作への応答のみ（SnackBar、ダイアログ、進捗バー）
- One orchestrated moment at most: なし
- Forbidden: 読み込み時のフェード/スライド、カードごとのホバー効果、祝福アニメーション

## 6. Writing

- Language: ja; sentence case
- CTA names the result: 電話帳に登録 → 電話帳に登録しました / 保存 → 保存しました
- Errors: 「連絡先の権限がありません。設定で許可してください」のように、起きたこと + 直し方
- Empty state: 「名刺を撮影するか、アルバムから選んでください」

## 7. Forbidden in this app

- 英語のフィールドキー（name / dept）を画面に出すこと。画面は日本語ラベル（氏名 / 部署）。
- 開発用語（JSON、golden、inbox、スパイク）を利用者向け文言に出すこと。
- ハードコードした色・サイズ、ALL-CAPS、ボタン文言の `→`、順序のない項目への番号

## 8. Stack notes

- Flutter: Material 3 `ThemeData` in `lib/theme.dart`; `Theme.of(context)`; `Semantics`; `MediaQuery.of(context).disableAnimations`; widget test for the review form (`test/card_form_test.dart`)

## Change log

- 2026-10-25: created from harness designing-ui template; first user-facing pass of the spike UI
