import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/ui/alpha_order.dart';

void main() {
  test('compareLabelsAlpha is case-insensitive and trims', () {
    expect(compareLabelsAlpha('Ada', 'bob'), lessThan(0));
    expect(compareLabelsAlpha('zoe', 'Mike'), greaterThan(0));
    expect(compareLabelsAlpha('  zoe', 'Mike'), greaterThan(0));
    expect(compareLabelsAlpha('Banana', 'apple'), greaterThan(0));
  });

  test('compareLabelsAlpha tiebreaks on the original string', () {
    expect(compareLabelsAlpha('Ada', 'ADA'), greaterThan(0));
    expect(compareLabelsAlpha('ada', 'Ada'), greaterThan(0));
  });

  test('sortedAlphaBy orders by label', () {
    expect(
      sortedAlphaBy(['zoe', 'Ada', 'mike'], (s) => s),
      ['Ada', 'mike', 'zoe'],
    );
  });
}
