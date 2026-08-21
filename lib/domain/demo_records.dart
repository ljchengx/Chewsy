import 'models.dart';

final demoRecords = <MealRecord>[
  MealRecord(
    restaurant: '巷口炭火烧烤',
    dishes: const ['烤牛油'],
    verdict: Verdict.keep,
    reasons: const ['锅气够'],
    photo: 'assets/images/hero_food.jpg',
    eatenAt: DateTime(2026, 8, 20, 19, 47),
    note: '锅气一上来，我又信了。',
  ),
  MealRecord(
    restaurant: '楼下粉面铺',
    dishes: const ['肥肠粉'],
    verdict: Verdict.skip,
    reasons: const ['汤太咸'],
    photo: 'assets/images/noodles.jpg',
    eatenAt: DateTime(2026, 8, 20, 12, 28),
    note: '这一碗，先绕开。',
  ),
  MealRecord(
    restaurant: '深夜小馆',
    dishes: const ['砂锅牛肉'],
    verdict: Verdict.keep,
    reasons: const ['下次还吃'],
    photo: 'assets/images/beef.jpg',
    eatenAt: DateTime(2026, 8, 19, 23, 19),
    note: '夜宵就该有点锅气。',
  ),
  MealRecord(
    restaurant: '周末家宴',
    dishes: const ['番茄火锅'],
    verdict: Verdict.keep,
    reasons: const ['人多更香'],
    photo: 'assets/images/hotpot.jpg',
    eatenAt: DateTime(2026, 8, 16, 18, 35),
    note: '适合一桌人慢慢吃。',
  ),
];
