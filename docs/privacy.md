# 名刺スキャン プライバシーポリシー / Privacy Policy

最終更新 / Last updated: 2026-11-02
公開 URL / Public URL: https://masanobu7423.github.io/meishi_ocr/privacy.html

## 日本語

名刺スキャン（パッケージ名 jp.tobishoku.meishi_ocr、以下「本アプリ」）は、名刺を撮影して内容を読み取り、端末の連絡先に登録・管理するアプリです。本ポリシーは、本アプリが利用者の情報をどのように扱うかを説明します。

### 1. 基本方針
本アプリは、名刺の画像・読み取った文字・連絡先など利用者の情報を、開発者のサーバーや第三者のサーバーに送信しません。広告 SDK は含みません。文字認識は端末内で行い、名刺の画像が端末の外に送られることはありません。

ただし、本アプリが使う Google の ML Kit（文字認識とドキュメントスキャナー）は、機能の診断と利用状況の分析のために、次の情報を暗号化した通信で Google に送ります。端末の情報（メーカー、機種、OS のバージョンなど）、アプリのパッケージ名とバージョン、処理の性能、機能の設定、入出力の大きさ、イベントの種類、エラーコード、インストールごとの識別子です。名刺の画像や読み取った文字の内容は含みません。詳しくは Google の説明（https://developers.google.com/ml-kit/android-data-disclosure ）をご覧ください。

このほかに端末の外へ情報が出るのは、第 4 項（OS による連絡先の同期）、第 6 項（利用者の操作による引き渡し）、第 8 項（Android のバックアップ）の場合だけです。

### 2. 端末内で扱う情報
- カメラで撮影した名刺の画像（表・裏）、およびアルバムやフォルダから取り込んだ画像
- 画像から読み取った文字と、利用者が確認・修正した項目（氏名、ふりがな、ローマ字、会社、部門、部署、役職、電話、携帯、FAX、メール、URL、郵便番号、住所、法人番号、建設業許可、宅建業免許、資格）
- 利用者が入力した項目（メモ、区分、職種、信頼度、関係者、次回連絡日、最終連絡日）
- 利用者の修正から学習した補正ルール（行と項目の対応、役職・部署の語彙、文字の誤認識の訂正）と、修正の履歴（名刺ごとの修正前後の値）
- 設定（登録先アカウントの種別と名前、職種の一覧、「自分の名刺」に選んだ名刺、バックアップを最後に端末の外へ共有した日）
- 自動バックアップ（アプリを起動した日に 1 回まで、最新の 5 つ）と、利用者が書き出した vCard・CSV
- 削除した名刺（第 8 項のとおり 7 日間）
- 動作の記録（エラーが起きた処理の名前、対象のファイル名（名刺のファイル名には氏名が含まれます）、エラーの文、画像の傾き補正の結果）。不具合の調査のために端末内にだけ残します

これらは端末内のアプリ専用領域（`Android/data/jp.tobishoku.meishi_ocr/files`）と、アプリのキャッシュに保存されます。利用者が自分で移動・共有しない限り、端末の外に出ることはありません（第 8 項の Android のバックアップを除きます）。

### 3. 連絡先へのアクセス
本アプリは、次の操作をしたときにのみ、端末の連絡先を読み書きします。
- 「電話帳に登録」「未登録の名刺を電話帳に登録」: 同じ人がすでに登録されていないかを、電話番号とメールアドレスで照合するために読み取ります。名刺の内容を連絡先として書き込みます。
- 照合で見つかった連絡先がある場合の統合画面: 利用者の選択に応じて、既存の連絡先を名刺の内容で更新する（統合）、既存の連絡先を削除して名刺を登録する、または端末の連絡先アプリで既存の連絡先を開きます。
- 「電話帳から取り込む」: 登録先として選んだアカウント（選んでいない場合は端末のすべてのアカウント）の連絡先を読み取ります。氏名、ふりがな、会社、部署、役職、電話（種類ごとに 1 件）、メール、URL、郵便番号、住所、メモを、名刺として本アプリ内に保存します。連絡先の写真は読み取りません。
- 電話帳と紐付いた名刺を保存したとき: 紐付いた連絡先を、名刺の内容で更新します。
- 「電話帳の内容を取り込む」: 紐付いた連絡先 1 件の現在の内容を読み取り、確認画面に表示します。

連絡先に書き込むとき、連絡先のメモ欄に、名刺のメモ、区分、職種、信頼度、関係者、次回連絡日、最終連絡日、法人番号、建設業許可、宅建業免許、資格、取込日を書き込みます。連絡先の内容は、第 4 項の同期の対象になります。本アプリが連絡先のデータを開発者や第三者に送ることはありません。

### 4. Google アカウントへの登録と同期
登録先として Google アカウントを選んだ場合、連絡先（第 3 項のメモ欄を含みます）は、Android の連絡先同期の仕組みによって、その Google アカウントの連絡先（Google コンタクト）に保存されます。この送信は端末の OS が行うもので、本アプリが Google のサーバーと直接通信することはありません。Google 側での取り扱いは Google のプライバシーポリシーに従います。端末のローカルアカウントを選べば、連絡先は端末内にとどまります。

### 5. Google Play 開発者サービス
撮影時の名刺の辺検出と歪み補正には、Google Play 開発者サービスが提供する ML Kit ドキュメントスキャナーを使います。文字認識とスキャナーのモジュールは、初回利用時に Google Play 開発者サービスがダウンロードすることがあります。処理そのものは端末内で行われ、画像は Google に送られません。診断情報の送信は第 1 項のとおりです。

### 6. 外部アプリへの引き渡し
次の引き渡しは、利用者の操作があったときだけ行います。引き渡した先での取り扱いは、それぞれのアプリのポリシーに従います。
- 「電話」「メール」「ウェブ」「地図」、一覧の電話ボタン: 電話番号、メールアドレス、URL、住所を、端末の電話・メール・ブラウザ・地図アプリに渡します。
- 共有: 選んだ名刺、全件の vCard と CSV、連絡予定（ics）、バックアップ zip を、端末の共有画面に渡します。送り先は利用者が選びます。vCard と CSV には、メモ、区分、職種、信頼度、関係者、連絡日なども含まれます。
- 「自分の名刺を送る」: 利用者が選んだ自分の名刺を、テキストまたは vCard で共有画面に渡します。こちらには、メモ・区分・職種・信頼度・関係者・連絡日を含めません。
- 「カレンダーに登録」: 予定のタイトル（氏名と会社）、日付、説明（電話・メール、本アプリからの登録であること）を、端末のカレンダーアプリの新規予定画面に渡します。保存するかどうかは利用者がカレンダーアプリで決めます。
- 「ファイルから選ぶ」（バックアップからの復元）: 端末のファイル選択画面で利用者が選んだファイルだけを読み取ります。読み取ったファイルはアプリのキャッシュに一時的に写し、復元が終わると削除します。

### 7. 権限
- カメラ: 名刺の撮影
- 連絡先の読み取り・書き込み: 第 3 項の操作
- ストレージの読み取り（Android 12 以前）・書き込み（Android 9 以前）: 写真の選択と撮影の部品が求めるもの。アプリが読み書きするのは、利用者が選んだ画像と、アプリ専用領域だけです
- ネットワークへのアクセス、ネットワークの状態の確認: 第 1 項の ML Kit の診断情報の送信

共有、カレンダーへの登録、ファイルの選択は、端末の標準の画面を使います。そのため、追加の権限は使いません。

### 8. 保存期間と削除
保存した情報は、利用者が削除するかアプリをアンインストールするまで端末内に残ります。
- 名刺を削除すると、その名刺はアプリ内のゴミ箱に移ります。7 日間は元に戻せます。7 日を過ぎると、アプリの起動時に、修正の履歴とともに完全に削除されます。
- 削除した名刺は、削除する前に作られた自動バックアップ（最新の 5 つ）と、利用者が書き出した vCard・CSV には残ります。自動バックアップは新しいものが作られると古い順に削除されます。
- アンインストールすると、アプリ専用領域の保存データ（ゴミ箱と自動バックアップを含む）はすべて削除されます。

Android のバックアップ: 端末の設定で Google へのバックアップが有効になっている場合、Android の仕組みにより、アプリ専用領域のデータ（名刺、画像、設定など）が、利用者の Google アカウントのバックアップに含まれることがあります。新しい端末に移ったときに復元されます。この送信は端末の OS が行い、Google 側での取り扱いは Google のポリシーに従います。端末の設定でバックアップを無効にすれば、送信されません。

連絡先に登録した情報は、端末の連絡先アプリ（Google アカウントの場合は Google コンタクト）から削除してください。利用者が自分で端末の外に移したり共有したりしたバックアップ・vCard・CSV は、利用者の管理下にあります。

### 9. 子どものプライバシー
本アプリはビジネス用途を想定しており、13 歳未満の子どもを対象としていません。

### 10. 本ポリシーの変更
本ポリシーを変更する場合は、このページを更新し、最終更新日を改めます。

### 11. お問い合わせ
開発者: 名刺スキャン 開発者（Google Play の掲載情報に記載）
メール: info@sunrisegroup.tokyo

## English

名刺スキャン (Meishi Scan, package jp.tobishoku.meishi_ocr, "the app") photographs business cards, recognises their text, and saves and manages them as contacts on the device. This policy explains how the app handles your information.

### 1. Principle
The app does not send your information (card images, recognised text, contacts) to the developer's servers or to any third-party server. It contains no advertising SDKs. Text recognition runs on the device, and card images never leave it.

However, Google's ML Kit, which the app uses for text recognition and the document scanner, sends the following to Google over an encrypted connection for diagnostics and usage analytics: device information (manufacturer, model, OS version and similar), the app's package name and version, performance metrics, feature configuration, input and output sizes, event types, error codes, and a per-installation identifier. It does not include card images or the recognised text. Google's description: https://developers.google.com/ml-kit/android-data-disclosure

Otherwise, information leaves the device only as described in section 4 (contact sync by the operating system), section 6 (hand-offs the user starts) and section 8 (Android backup).

### 2. Data handled on the device
- Card photos (front and back) taken with the camera or imported from the album or a folder
- Text recognised from those photos and the fields the user reviews and corrects (name, reading, romanised name, company, division, department, title, phone, mobile, fax, email, URL, postal code, address, corporate number, construction licence, real-estate licence, qualifications)
- Fields the user enters (memo, category, trade, trust rating, related people, next contact date, last contact date)
- Correction rules learned from the user's edits (line-to-field mapping, title/department vocabulary, character fixes) and a correction history (the values before and after each edit, per card)
- Settings (type and name of the account to register into, the trade list, the card chosen as "my card", the date a backup was last shared off the device)
- Automatic backups (at most one per day the app is opened, the latest five kept) and vCard / CSV files the user exports
- Deleted cards (kept for 7 days, see section 8)
- An activity log (the name of the step that failed, the file it concerned (card file names include the person's name), the error text, and image straightening results), kept on the device only, for troubleshooting

All of this is stored in the app's private folder on the device (`Android/data/jp.tobishoku.meishi_ocr/files`) and its cache, and does not leave the device unless the user moves or shares it (except for the Android backup in section 8).

### 3. Contacts access
The app reads or writes the device contacts only when the user does one of the following:
- "Register to contacts" or "Register all unregistered cards": contacts are read to check, by phone number and email, whether the same person already exists, and the card is written as a contact.
- The merge screen shown when a match is found: depending on the user's choice, the existing contact is updated with the card's values (merge), the existing contact is deleted and the card registered, or the existing contact is opened in the device's contacts app.
- "Import from contacts": the contacts of the account chosen for registration (all accounts on the device if none is chosen) are read, and their name, reading, company, department, title, phone numbers (one per kind), email, URL, postal code, address and notes are saved in the app as cards. Contact photos are not read.
- Saving a card linked to a contact: the linked contact is updated with the card's values.
- "Take in the contact's values": the current values of the one linked contact are read and shown on the review screen.

When writing a contact, the app puts the card's memo, category, trade, trust rating, related people, next and last contact dates, corporate number, construction and real-estate licences, qualifications and scan date into the contact's notes. Contacts are subject to the sync in section 4. The app never sends contact data to the developer or to any third party.

### 4. Registering into a Google account
If the user chooses a Google account as the destination, the contact (including the notes in section 3) is stored in that account's contacts (Google Contacts) through Android's contact synchronisation. This transfer is performed by the operating system; the app does not communicate with Google's servers itself. Google's handling of that data is governed by Google's privacy policy. Choosing a local device account keeps the contact on the device.

### 5. Google Play services
Card edge detection and perspective correction at capture use the ML Kit document scanner provided by Google Play services. Google Play services may download the text-recognition and scanner modules on first use. The processing itself runs on the device; images are not sent to Google. Diagnostics are sent as described in section 1.

### 6. Hand-off to other apps
The following hand-offs happen only when the user starts them. Handling after the hand-off is governed by the receiving app's policy.
- "Phone", "Mail", "Web", "Map" and the call button in the lists: the phone number, email address, URL or address is passed to the phone, mail, browser or map app on the device.
- Sharing: selected cards, all cards as vCard or CSV, follow-ups as an iCalendar (ics) file and a backup zip are passed to the system share sheet; the user chooses the destination. vCard and CSV files include the memo, category, trade, trust rating, related people and contact dates.
- "Send my card": the card the user chose as their own is passed to the share sheet as text or vCard, without the memo, category, trade, trust rating, related people or contact dates.
- "Add to calendar": the event title (name and company), date and description (phone, email, and a note that it came from the app) are passed to the new-event screen of the device's calendar app; the user decides there whether to save it.
- "Choose a file" (restore from a backup): only the file the user picks in the system file picker is read. It is copied into the app's cache temporarily and deleted when the restore finishes.

### 7. Permissions
- Camera: photographing cards
- Read/write contacts: the actions in section 3
- Read storage (Android 12 and earlier) and write storage (Android 9 and earlier): requested by the photo picker and camera components; the app only reads images the user picks and its own private folder
- Network access and network state: ML Kit's diagnostics in section 1

Sharing, adding to the calendar and choosing a file use the system's standard screens and need no additional permission.

### 8. Retention and deletion
Stored data remains on the device until the user deletes it or uninstalls the app.
- A deleted card moves to the app's trash. It can be restored for 7 days; after that it is deleted for good, together with its correction history, when the app starts.
- A deleted card remains in automatic backups made before the deletion (the latest five) and in vCard / CSV files the user exported. Automatic backups are deleted oldest first as new ones are made.
- Uninstalling deletes everything in the app's private folder, including the trash and the automatic backups.

Android backup: if backup to Google is turned on in the device settings, Android may include the app's private data (cards, images, settings) in the user's Google account backup and restore it on a new device. This transfer is performed by the operating system, and Google's handling of it is governed by Google's policies. Turning backup off in the device settings stops it.

Contacts already registered can be removed from the device's contacts app (or Google Contacts for a Google account). Backups, vCard and CSV files the user has moved or shared off the device are under the user's control.

### 9. Children
The app is intended for business use and is not directed at children under 13.

### 10. Changes
Changes to this policy are published on this page with a new "last updated" date.

### 11. Contact
Developer: the developer named on the app's Google Play listing
Email: info@sunrisegroup.tokyo
