// Google 電話帳との同期: contacts on the device (the Google account Android
// syncs) ↔ cards. Pull = fieldsFromContact + importPlan; push = applyCard;
// the link is the contact id stored on the card.
import 'dart:io';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meishi_ocr/ocr/card_note.dart';
import 'package:meishi_ocr/ocr/card_status.dart';
import 'package:meishi_ocr/ocr/card_store.dart';
import 'package:meishi_ocr/ocr/contact_mapper.dart';
import 'package:meishi_ocr/ocr/extractor.dart';
import 'package:meishi_ocr/ocr/history.dart';
import 'package:meishi_ocr/ocr/sync.dart';
import 'package:meishi_ocr/ocr/vault_index.dart';
import 'package:meishi_ocr/ocr/vcard_export.dart';

CardFields _card() => CardFields()
  ..name = '山田 太郎'
  ..nameKana = 'やまだ たろう'
  ..company = '株式会社サンライズ'
  ..dept = '工事部'
  ..title = '現場監督'
  ..phone = '03-1234-5678'
  ..mobile = '090-1234-5678'
  ..fax = '03-1234-5679'
  ..email = 'taro@example.com'
  ..url = 'https://example.com'
  ..postal = '100-0001'
  ..address = '東京都千代田区1-1'
  ..memo = '展示会で交換'
  ..category = '協力会社'
  ..job = '鳶'
  ..trust = '4'
  ..related = '佐藤, 鈴木'
  ..corpNo = '1234567890123'
  ..qualifications = '一級建築士';

void main() {
  final when = DateTime(2026, 10, 26);

  test('fieldsFromContact reads back what toContact wrote, and keeps the contact id', () {
    final c = toContact(_card(), scannedAt: when, source: 'k01.json').copyWith(id: '42');
    final f = fieldsFromContact(c);
    final j = f.toJson();
    for (final k in ['name', 'company', 'dept', 'title', 'phone', 'mobile', 'fax', 'email', 'url', 'postal',
        'address', 'memo', 'category', 'job', 'trust', 'related', 'corpNo', 'qualifications']) {
      expect(j[k], _card().toJson()[k], reason: k);
    }
    expect(f.nameKana, 'ヤマダ タロウ', reason: 'phonetic name, katakana as stored');
    expect(f.contactId, '42');
    expect(f.memo, isNot(contains('名刺取込')), reason: 'the link line is not a memo');
  });

  test('fieldsFromContact copes with a plain contact: display name only, no notes', () {
    final f = fieldsFromContact(Contact(id: '7', displayName: '鈴木 一郎', phones: [Phone(number: '0120-000-000')]));
    // The plugin's default phone label is mobile, so an unlabelled number lands there.
    expect((f.name, f.mobile, f.memo, f.contactId), ('鈴木 一郎', '0120-000-000', null, '7'));
  });

  test('applyCard puts the card onto the existing contact and keeps its identity', () {
    final existing = Contact(
      id: '42',
      displayName: '旧 名前',
      phones: [Phone(number: '000')],
      emails: [Email(address: 'old@example.com')],
      notes: [Note(note: '古いメモ')],
    );
    final c = applyCard(existing, _card(), scannedAt: when);
    expect(c.id, '42');
    expect(c.displayName, '山田 太郎');
    expect(c.phones.map((p) => p.number), ['03-1234-5678', '090-1234-5678', '03-1234-5679', '000'],
        reason: 'the card first, then what only the contact had');
    expect(c.emails.map((e) => e.address), ['taro@example.com', 'old@example.com']);
    expect('職種: 鳶'.allMatches(c.notes.single.note).length, 1);
    expect(c.notes.single.note, contains('古いメモ'), reason: 'a free note added in Google survives');
    // Pushing twice adds nothing.
    final again = applyCard(c, _card(), scannedAt: when);
    expect(again.phones.length, 4);
    expect(again.notes.single.note, c.notes.single.note);
  });

  test('importPlan: new contacts are created; linked, matching and nameless ones are skipped', () {
    final cards = [
      const CardSummary(noteStem: 'a', stem: 'k01', name: '山田 太郎', phone: '03-1234-5678', contactId: '1'),
      const CardSummary(noteStem: 'b', stem: 'k02', name: '鈴木 一郎', email: 'Ichiro@Example.com'),
    ];
    final contacts = [
      Contact(id: '1', displayName: '山田 太郎'),
      Contact(id: '2', displayName: '鈴木 一郎', emails: [Email(address: 'ichiro@example.com')]),
      Contact(id: '3', displayName: '佐藤 花子', phones: [Phone(number: '+81 3 1234 5678')]),
      Contact(id: '4', displayName: '田中 次郎', phones: [Phone(number: '090-0000-0000')]),
      Contact(id: '5', displayName: ''),
    ];
    final plan = importPlan(contacts, cards);
    expect({for (final p in plan) p.contact.id: p.action}, {
      '1': ImportAction.skipLinked,
      '2': ImportAction.skipExisting,
      '3': ImportAction.skipExisting,
      '4': ImportAction.create,
      '5': ImportAction.skipNoName,
    });
  });

  test('the contact id travels through JSON, frontmatter and the summary', () {
    final f = _card()..contactId = '42';
    expect(fieldsFromJson(f.toJson()).contactId, '42');
    final md = cardNoteMarkdown(f, scannedAt: when);
    expect(parseFrontmatter(md)['contact_id'], '42');
    expect(fieldsFromFrontmatter(parseFrontmatter(md)).contactId, '42');
    expect(cardSummaries({'x': md}).single.contactId, '42');
    expect(md, isNot(contains('#contact')), reason: 'an id is not a tag');
  });

  test('setStatus can record the contact id; a card from the phone book saves without OCR lines', () async {
    final tmp = await Directory.systemTemp.createTemp('meishi_sync_');
    addTearDown(() => tmp.delete(recursive: true));
    final store = CardStore(tmp);
    await store.saveCard(stem: 'pb_9', front: const [], back: const [], expected: _card().toJson(),
        status: CardStatus.registered);
    expect(await store.setStatus('pb_9', CardStatus.registered, contactId: '9'), isTrue);
    final card = await store.loadCard('pb_9');
    expect((card!.expected['contactId'], card.status), ('9', CardStatus.registered));
    expect(parseFrontmatter((await store.notes()).values.single)['contact_id'], '9');
  });

  group('pullChanges', () {
    final current = {
      'name': '山田 太郎', 'nameKana': 'やまだ たろう', 'division': '営業本部', 'dept': '営業部',
      'phone': '03-1234-5678', 'email': '', 'memo': '展示会',
    };
    test('takes what the contact has and the form lacks or differs in', () {
      final theirs = {
        'name': '山田 太郎', 'nameKana': 'ヤマダ タロウ', 'dept': '営業本部 営業部',
        'phone': '03-9999-0000', 'email': 'new@example.com', 'memo': null, 'contactId': '42',
      };
      expect(pullChanges(current, theirs), {'phone': '03-9999-0000', 'email': 'new@example.com'});
    });
    test('the division prefix written by toContact is taken off the department', () {
      expect(pullChanges(current, {'dept': '営業本部 工事部'}), {'dept': '工事部'});
      expect(pullChanges({...current, 'division': ''}, {'dept': '営業本部 営業部'}), {'dept': '営業本部 営業部'});
    });
    test('a hiragana reading equal to the stored katakana is not a change; empty values never overwrite', () {
      expect(pullChanges(current, {'nameKana': 'ヤマダ タロウ', 'memo': '', 'name': null}), isEmpty);
      expect(pullChanges(current, {'nameKana': 'ヤマダ ハナコ'}), {'nameKana': 'ヤマダ ハナコ'});
    });
    test('only form fields are pulled (hidden ones like contactId are not)', () {
      expect(pullChanges(current, {'contactId': '99'}), isEmpty);
    });
  });
}
