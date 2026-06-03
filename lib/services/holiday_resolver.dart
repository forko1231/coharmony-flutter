// Port of `Services/HolidayResolver.cs`. Pure logic — resolves named holiday
// rules to actual dates for a given year (fixed-date + nth-weekday + computed).
//
// Weekday numbering: C# DayOfWeek is Sunday=0..Saturday=6; Dart DateTime.weekday
// is Monday=1..Sunday=7. We normalise to the C# scheme via `weekday % 7` and
// compute results by day-of-month number (matching C#'s calendar-based AddDays).

class HolidayDefinition {
  const HolidayDefinition(this.rule, this.displayName);
  final String rule;
  final String displayName;
}

class HolidayCategory {
  const HolidayCategory(this.name, this.holidays);
  final String name;
  final List<HolidayDefinition> holidays;
}

class HolidayResolver {
  HolidayResolver._();

  // C# DayOfWeek integer values.
  static const int _sun = 0, _mon = 1, _thu = 4;

  static const List<HolidayCategory> categories = [
    HolidayCategory('Major US Holidays', [
      HolidayDefinition('new-years-day', "New Year's Day"),
      HolidayDefinition('mlk-day', 'Martin Luther King Jr. Day'),
      HolidayDefinition('presidents-day', "Presidents' Day"),
      HolidayDefinition('memorial-day', 'Memorial Day'),
      HolidayDefinition('independence-day', 'Independence Day (July 4th)'),
      HolidayDefinition('labor-day', 'Labor Day'),
      HolidayDefinition('columbus-day', 'Columbus Day'),
      HolidayDefinition('veterans-day', 'Veterans Day'),
      HolidayDefinition('thanksgiving', 'Thanksgiving'),
      HolidayDefinition('christmas-eve', 'Christmas Eve'),
      HolidayDefinition('christmas', 'Christmas Day'),
      HolidayDefinition('new-years-eve', "New Year's Eve"),
    ]),
    HolidayCategory('Family & Parent Holidays', [
      HolidayDefinition('mothers-day', "Mother's Day"),
      HolidayDefinition('fathers-day', "Father's Day"),
      HolidayDefinition('valentines-day', "Valentine's Day"),
      HolidayDefinition('parents-day', "Parents' Day"),
    ]),
    HolidayCategory('School & Seasonal', [
      HolidayDefinition('easter', 'Easter Sunday'),
      HolidayDefinition('good-friday', 'Good Friday'),
      HolidayDefinition('halloween', 'Halloween'),
      HolidayDefinition('spring-break-start', 'Spring Break Start (Mar 15)'),
      HolidayDefinition('spring-break-end', 'Spring Break End (Mar 22)'),
      HolidayDefinition('summer-start', 'Summer Break Start (Jun 1)'),
      HolidayDefinition('summer-end', 'Summer Break End (Aug 15)'),
      HolidayDefinition('winter-break-start', 'Winter Break Start (Dec 20)'),
      HolidayDefinition('winter-break-end', 'Winter Break End (Jan 3)'),
    ]),
    HolidayCategory('Other Holidays', [
      HolidayDefinition('groundhog-day', 'Groundhog Day'),
      HolidayDefinition('st-patricks-day', "St. Patrick's Day"),
      HolidayDefinition('earth-day', 'Earth Day'),
      HolidayDefinition('cinco-de-mayo', 'Cinco de Mayo'),
      HolidayDefinition('juneteenth', 'Juneteenth'),
      HolidayDefinition('indigenous-peoples-day', "Indigenous Peoples' Day"),
      HolidayDefinition('election-day', 'Election Day'),
    ]),
  ];

  static final Map<String, HolidayDefinition> _allHolidays = {
    for (final cat in categories)
      for (final h in cat.holidays) h.rule.toLowerCase(): h,
  };

  static List<HolidayDefinition> getAllHolidays() => _allHolidays.values.toList();

  static String getDisplayName(String rule) =>
      _allHolidays[rule.toLowerCase()]?.displayName ?? rule;

  /// Resolves a holiday rule to an actual date for [year]. Null if unrecognized.
  static DateTime? resolveDate(String? holidayRule, int year) {
    if (holidayRule == null || holidayRule.isEmpty) return null;

    switch (holidayRule.toLowerCase()) {
      // Fixed-date holidays
      case 'new-years-day':
        return DateTime(year, 1, 1);
      case 'groundhog-day':
        return DateTime(year, 2, 2);
      case 'valentines-day':
        return DateTime(year, 2, 14);
      case 'st-patricks-day':
        return DateTime(year, 3, 17);
      case 'spring-break-start':
        return DateTime(year, 3, 15);
      case 'spring-break-end':
        return DateTime(year, 3, 22);
      case 'earth-day':
        return DateTime(year, 4, 22);
      case 'cinco-de-mayo':
        return DateTime(year, 5, 5);
      case 'summer-start':
        return DateTime(year, 6, 1);
      case 'juneteenth':
        return DateTime(year, 6, 19);
      case 'independence-day':
        return DateTime(year, 7, 4);
      case 'summer-end':
        return DateTime(year, 8, 15);
      case 'halloween':
        return DateTime(year, 10, 31);
      case 'veterans-day':
        return DateTime(year, 11, 11);
      case 'winter-break-start':
        return DateTime(year, 12, 20);
      case 'christmas-eve':
        return DateTime(year, 12, 24);
      case 'christmas':
        return DateTime(year, 12, 25);
      case 'new-years-eve':
        return DateTime(year, 12, 31);
      case 'winter-break-end':
        return DateTime(year + 1, 1, 3); // Jan 3 of next year

      // Nth weekday of month holidays
      case 'mlk-day':
        return _nthWeekday(year, 1, _mon, 3); // 3rd Monday of January
      case 'presidents-day':
        return _nthWeekday(year, 2, _mon, 3); // 3rd Monday of February
      case 'mothers-day':
        return _nthWeekday(year, 5, _sun, 2); // 2nd Sunday of May
      case 'memorial-day':
        return _lastWeekday(year, 5, _mon); // Last Monday of May
      case 'fathers-day':
        return _nthWeekday(year, 6, _sun, 3); // 3rd Sunday of June
      case 'parents-day':
        return _nthWeekday(year, 7, _sun, 4); // 4th Sunday of July
      case 'labor-day':
        return _nthWeekday(year, 9, _mon, 1); // 1st Monday of September
      case 'columbus-day':
      case 'indigenous-peoples-day':
        return _nthWeekday(year, 10, _mon, 2); // 2nd Monday of October
      case 'thanksgiving':
        return _nthWeekday(year, 11, _thu, 4); // 4th Thursday of November
      case 'election-day':
        return _electionDay(year); // 1st Tuesday after 1st Monday in November

      // Computed holidays
      case 'easter':
        return _computeEaster(year);
      case 'good-friday':
        final easter = _computeEaster(year);
        final gf = easter.subtract(const Duration(days: 2));
        return DateTime(gf.year, gf.month, gf.day);

      default:
        return null;
    }
  }

  static int _csDow(DateTime d) => d.weekday % 7; // Mon..Sun(1..7) -> Sun..Sat(0..6)

  static DateTime _nthWeekday(int year, int month, int dayOfWeek, int n) {
    final first = DateTime(year, month, 1);
    final daysUntil = (dayOfWeek - _csDow(first) + 7) % 7;
    return DateTime(year, month, 1 + daysUntil + (n - 1) * 7);
  }

  static DateTime _lastWeekday(int year, int month, int dayOfWeek) {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final last = DateTime(year, month, daysInMonth);
    final daysBack = (_csDow(last) - dayOfWeek + 7) % 7;
    return DateTime(year, month, daysInMonth - daysBack);
  }

  static DateTime _electionDay(int year) {
    final firstMonday = _nthWeekday(year, 11, _mon, 1);
    return DateTime(year, 11, firstMonday.day + 1); // Tuesday after
  }

  /// Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
  static DateTime _computeEaster(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }
}
