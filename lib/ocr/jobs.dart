/// 職種 the form offers before the user edits the list: construction trades
/// first (the app's audience), then a few office roles. `jobCategory` may
/// guess a value outside this list (技術開発, 管理, …); it then shows as a
/// value in use. The user's own list lives in `<root>/jobs.json` (CardStore).
const defaultJobs = [
  '鳶', '足場', '鉄筋', '型枠', '大工', '左官', '鉄骨', '溶接', '土木', '舗装', '解体', '重機',
  '電気', '設備', '配管', '空調', '塗装', '防水', '内装', '板金', '屋根', '測量',
  '施工管理', '設計', '不動産', '営業', '経営', '事務', 'その他',
];
