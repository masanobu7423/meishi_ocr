/// Where a saved card is in its life: captured in a burst and not yet looked
/// at, reviewed (saved from the form), or registered in the address book.
/// Stored as the enum name in golden JSON and as the label in note
/// frontmatter; cards saved before this existed count as reviewed.
enum CardStatus {
  unreviewed('未確認'),
  reviewed('確認済'),
  registered('登録済');

  const CardStatus(this.label);
  final String label;
}

CardStatus parseStatus(String? s) => CardStatus.values.firstWhere(
    (v) => v.name == s || v.label == s,
    orElse: () => CardStatus.reviewed);
