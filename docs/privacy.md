# 名刺スキャン プライバシーポリシー / Privacy Policy

最終更新 / Last updated: 2026-10-25
公開 URL / Public URL: https://masanobu7423.github.io/meishi_ocr/privacy.html

## 日本語

名刺スキャン（パッケージ名 jp.tobishoku.meishi_ocr、以下「本アプリ」）は、名刺を撮影して内容を読み取り、端末の連絡先に登録するアプリです。本ポリシーは、本アプリが利用者の情報をどのように扱うかを説明します。

### 1. 基本方針
本アプリは、利用者の情報を開発者のサーバーや第三者のサーバーに送信しません。本アプリ自身はインターネット通信を行わず、解析（アナリティクス）SDK や広告 SDK も含みません。文字認識のモデルはアプリに同梱されており、名刺の画像が端末の外に送られることはありません。

### 2. 端末内で扱う情報
- カメラで撮影した名刺の画像（表・裏）、およびアルバムから選んだ画像
- 画像から読み取った文字と、利用者が修正した項目（氏名、ふりがな、会社、部署、役職、電話、携帯、FAX、メール、URL、郵便番号、住所）
- 利用者が入力したメモ
- 利用者の修正から学習した補正ルール（行と項目の対応、役職・部署の語彙、文字の誤認識の訂正）
- 設定（登録先アカウントの種別と名前）

これらは端末内のアプリ専用領域（`Android/data/jp.tobishoku.meishi_ocr/files`）にのみ保存されます。Obsidian 形式のノート、vCard、バックアップ zip も同じ領域に書き出され、利用者が自分で移動・共有しない限り端末の外に出ることはありません。

### 3. 連絡先へのアクセス
本アプリは、利用者が「電話帳に登録」または「未登録をまとめて登録」を押したときにのみ連絡先を読み書きします。読み取りは、同じ人がすでに登録されていないかを電話番号とメールアドレスで照合するため、および統合画面で既存の連絡先を表示するためだけに使います。連絡先データを本アプリの外に送ることはありません。

### 4. Google アカウントへの登録と同期
登録先として Google アカウントを選んだ場合、連絡先は Android の連絡先同期の仕組みによって、その Google アカウントの連絡先（Google コンタクト）に保存されます。この送信は端末の OS が行うもので、本アプリが Google のサーバーと直接通信することはありません。Google 側での取り扱いは Google のプライバシーポリシーに従います。端末のローカルアカウントを選べば、連絡先は端末内にとどまります。

### 5. Google Play 開発者サービス
撮影時の名刺の辺検出と歪み補正には、Google Play 開発者サービスが提供する ML Kit ドキュメントスキャナーを使います。この機能のモジュールは初回利用時に Google Play 開発者サービスがダウンロードすることがあります。処理そのものは端末内で行われ、画像は Google に送られません。

### 6. 外部アプリへの引き渡し
名刺の確認画面で「電話」「メール」「ウェブ」「地図」を押すと、その電話番号、メールアドレス、URL、住所を、端末にインストールされている電話・メール・ブラウザ・地図アプリに渡します。渡した先での取り扱いは、それぞれのアプリのポリシーに従います。引き渡しは利用者の操作があったときだけ行います。

### 7. 権限
- カメラ: 名刺の撮影
- 連絡先の読み取り・書き込み: 第 3 項の照合と登録
- 写真（アルバム）: 既存の写真からの取り込み（端末の写真選択画面を使い、選んだ画像だけを受け取ります）

### 8. 保存期間と削除
保存した情報は、利用者が削除するかアプリをアンインストールするまで端末内に残ります。アンインストールすると、アプリ専用領域の保存データはすべて削除されます。連絡先に登録した情報は端末の連絡先アプリ（Google アカウントの場合は Google コンタクト）から削除してください。利用者が自分で端末の外に移したバックアップや vCard は、利用者の管理下にあります。

### 9. 子どものプライバシー
本アプリはビジネス用途を想定しており、13 歳未満の子どもを対象としていません。

### 10. 本ポリシーの変更
本ポリシーを変更する場合は、このページを更新し、最終更新日を改めます。

### 11. お問い合わせ
開発者: 名刺スキャン 開発者（Google Play の掲載情報に記載）
メール: info@sunrisegroup.tokyo

## English

名刺スキャン (Meishi Scan, package jp.tobishoku.meishi_ocr, "the app") photographs business cards, recognises their text, and saves contacts to the device address book. This policy explains how the app handles your information.

### 1. Principle
The app does not send any user data to the developer's servers or to any third-party server. The app itself makes no network connections and contains no analytics or advertising SDKs. The text-recognition model is bundled with the app, so card images never leave the device.

### 2. Data handled on the device
- Card photos (front and back) taken with the camera or chosen from the album
- Text recognised from those photos and the fields the user corrects (name, reading, company, department, title, phone, mobile, fax, email, URL, postal code, address)
- Memos the user types
- Correction rules learned from the user's edits (line-to-field mapping, title/department vocabulary, character fixes)
- Settings (type and name of the account to register into)

All of this is stored only in the app's private folder on the device (`Android/data/jp.tobishoku.meishi_ocr/files`). Obsidian-style notes, vCard files and backup zips are written to the same folder and never leave the device unless the user moves or shares them.

### 3. Contacts access
The app reads and writes contacts only when the user taps "Register to contacts" or "Register all unregistered cards". Reading is used solely to check, by phone number and email, whether the same person already exists, and to show the existing contact on the merge screen. Contact data is never transmitted outside the app.

### 4. Registering into a Google account
If the user chooses a Google account as the destination, the contact is stored in that account's contacts (Google Contacts) through Android's contact synchronisation. This transfer is performed by the operating system; the app does not communicate with Google's servers itself. Google's handling of that data is governed by Google's privacy policy. Choosing a local device account keeps the contact on the device.

### 5. Google Play services
Card edge detection and perspective correction at capture use the ML Kit document scanner provided by Google Play services. Google Play services may download this module on first use. The processing itself runs on the device; images are not sent to Google.

### 6. Hand-off to other apps
Tapping "Phone", "Mail", "Web" or "Map" on a card passes that phone number, email address, URL or address to the phone, mail, browser or map app installed on the device. Handling after the hand-off is governed by those apps' policies. A hand-off happens only on the user's tap.

### 7. Permissions
- Camera: photographing cards
- Read/write contacts: the duplicate check and registration in section 3
- Photos (album): importing existing photos through the system photo picker; only the chosen images are received

### 8. Retention and deletion
Stored data remains on the device until the user deletes it or uninstalls the app. Uninstalling deletes everything in the app's private folder. Contacts already registered can be removed from the device's contacts app (or Google Contacts for a Google account). Backups and vCard files the user has moved off the device are under the user's control.

### 9. Children
The app is intended for business use and is not directed at children under 13.

### 10. Changes
Changes to this policy are published on this page with a new "last updated" date.

### 11. Contact
Developer: the developer named on the app's Google Play listing
Email: info@sunrisegroup.tokyo
