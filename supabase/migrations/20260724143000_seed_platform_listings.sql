alter table public.listings alter column owner_id drop not null;

insert into public.listings
  (owner_id, title, category, game_mode, rank_name, coins, feature, unit_price, max_days, deposit, proof_path, status, available)
values
  (null, '亿级哈夫币 · 满改枪库', 'wealth', '烽火地带', '钻石', 12800, '典藏外观18件', 120, 7, 200, 'platform/seed-071', 'approved', true),
  (null, '高段位 · 战神账号', 'rank', '全面战场', '战神', 6800, '全干员解锁', 150, 3, 300, 'platform/seed-114', 'approved', true),
  (null, '新手畅玩 · 免押套餐', 'starter', '烽火地带', '青铜', 1500, '基础枪械齐全', 80, 7, 0, 'platform/seed-208', 'approved', true),
  (null, '收藏家 · 典藏皮肤库', 'wealth', '双模式', '铂金', 7600, '典藏外观41件', 180, 7, 300, 'platform/seed-327', 'approved', true),
  (null, '冲分专用 · 全面战场', 'rank', '全面战场', '王牌', 5000, '赛季胜率68%', 100, 3, 200, 'platform/seed-416', 'approved', false),
  (null, '轻装体验 · 标准账号', 'starter', '双模式', '白银', 3000, '常用干员解锁', 90, 7, 100, 'platform/seed-552', 'approved', true);
