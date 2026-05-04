/// Preprocesses raw text for TTS: expands numbers, abbreviations, currency,
/// time expressions, etc. into speakable words.
///
/// Ported from KokoroTTS Python source (kokorotts/preprocess.py).
class TextPreprocessor {
  String process(String text) {
    text = _normalizeWhitespace(text);
    text = _removeUrls(text);
    text = _expandContractions(text);
    text = _normalizeLeadingDecimals(text);
    text = _expandCurrency(text);
    text = _expandPercentages(text);
    text = _expandTime(text);
    text = _expandOrdinals(text);
    text = _expandUnits(text);
    text = _expandFractions(text);
    text = _expandPhoneNumbers(text);
    text = _expandRanges(text);
    text = _expandModelNames(text);
    text = _replaceNumbers(text);
    text = text.toLowerCase();
    text = _normalizeWhitespace(text);
    return text;
  }

  // ── Number to words ──

  static const _ones = [
    '',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];

  static const _tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];

  static const _scales = ['', 'thousand', 'million', 'billion', 'trillion'];

  static const _ordinalExceptions = {
    'one': 'first',
    'two': 'second',
    'three': 'third',
    'four': 'fourth',
    'five': 'fifth',
    'six': 'sixth',
    'seven': 'seventh',
    'eight': 'eighth',
    'nine': 'ninth',
    'twelve': 'twelfth',
  };

  static String _threeDigitsToWords(int n) {
    if (n == 0) return '';
    final parts = <String>[];
    final hundreds = n ~/ 100;
    final remainder = n % 100;
    if (hundreds > 0) parts.add('${_ones[hundreds]} hundred');
    if (remainder < 20) {
      if (remainder > 0) parts.add(_ones[remainder]);
    } else {
      final tensWord = _tens[remainder ~/ 10];
      final onesWord = _ones[remainder % 10];
      parts.add(onesWord.isNotEmpty ? '$tensWord-$onesWord' : tensWord);
    }
    return parts.join(' ');
  }

  static String numberToWords(int n) {
    if (n == 0) return 'zero';
    if (n < 0) return 'negative ${numberToWords(-n)}';
    if (n >= 100 && n <= 9999 && n % 100 == 0 && n % 1000 != 0) {
      final h = n ~/ 100;
      if (h < 20) return '${_ones[h]} hundred';
    }
    final parts = <String>[];
    var remaining = n;
    for (var i = 0; i < _scales.length; i++) {
      final chunk = remaining % 1000;
      if (chunk > 0) {
        final w = _threeDigitsToWords(chunk);
        parts.add(_scales[i].isNotEmpty ? '$w ${_scales[i]}' : w);
      }
      remaining ~/= 1000;
      if (remaining == 0) break;
    }
    return parts.reversed.join(' ');
  }

  static String _floatToWords(String value) {
    final negative = value.startsWith('-');
    var s = negative ? value.substring(1) : value;
    if (s.contains('.')) {
      final parts = s.split('.');
      final intWords = numberToWords(
        int.parse(parts[0].isEmpty ? '0' : parts[0]),
      );
      final digitNames = ['zero', ..._ones.sublist(1)];
      final decWords = parts[1]
          .split('')
          .map((d) => digitNames[int.parse(d)])
          .join(' ');
      final result = '$intWords point $decWords';
      return negative ? 'negative $result' : result;
    }
    return numberToWords(int.parse(s));
  }

  static String _ordinalSuffix(int n) {
    final word = numberToWords(n);
    String prefix, last, joiner;
    if (word.contains('-')) {
      final idx = word.lastIndexOf('-');
      prefix = word.substring(0, idx);
      last = word.substring(idx + 1);
      joiner = '-';
    } else if (word.contains(' ')) {
      final idx = word.lastIndexOf(' ');
      prefix = word.substring(0, idx);
      last = word.substring(idx + 1);
      joiner = ' ';
    } else {
      prefix = '';
      last = word;
      joiner = '';
    }

    final exception = _ordinalExceptions[last];
    String lastOrd;
    if (exception != null) {
      lastOrd = exception;
    } else if (last.endsWith('t')) {
      lastOrd = '${last}h';
    } else if (last.endsWith('e')) {
      lastOrd = '${last.substring(0, last.length - 1)}th';
    } else {
      lastOrd = '${last}th';
    }
    return prefix.isNotEmpty ? '$prefix$joiner$lastOrd' : lastOrd;
  }

  // ── Regex expansions ──

  String _removeUrls(String text) =>
      text.replaceAll(RegExp(r'https?://\S+|www\.\S+'), '');

  String _expandContractions(String text) {
    const map = {
      r"\bcan't\b": 'cannot',
      r"\bwon't\b": 'will not',
      r"\bain't\b": 'is not',
      r"\blet's\b": 'let us',
      r"\bit's\b": 'it is',
    };
    for (final e in map.entries) {
      text = text.replaceAll(RegExp(e.key, caseSensitive: false), e.value);
    }
    text = text.replaceAllMapped(
      RegExp(r"\b(\w+)n't\b", caseSensitive: false),
      (m) => '${m[1]} not',
    );
    text = text.replaceAllMapped(
      RegExp(r"\b(\w+)'re\b", caseSensitive: false),
      (m) => '${m[1]} are',
    );
    text = text.replaceAllMapped(
      RegExp(r"\b(\w+)'ve\b", caseSensitive: false),
      (m) => '${m[1]} have',
    );
    text = text.replaceAllMapped(
      RegExp(r"\b(\w+)'ll\b", caseSensitive: false),
      (m) => '${m[1]} will',
    );
    text = text.replaceAllMapped(
      RegExp(r"\b(\w+)'d\b", caseSensitive: false),
      (m) => '${m[1]} would',
    );
    text = text.replaceAllMapped(
      RegExp(r"\b(\w+)'m\b", caseSensitive: false),
      (m) => '${m[1]} am',
    );
    return text;
  }

  String _normalizeLeadingDecimals(String text) {
    text = text.replaceAllMapped(
      RegExp(r'(?<!\d)(-)\.([\d])'),
      (m) => '${m[1]}0.${m[2]}',
    );
    return text.replaceAllMapped(
      RegExp(r'(?<!\d)\.([\d])'),
      (m) => '0.${m[1]}',
    );
  }

  String _expandCurrency(String text) {
    const symbols = {r'$': 'dollar', '€': 'euro', '£': 'pound', '¥': 'yen'};
    const scaleMap = {
      'K': 'thousand',
      'M': 'million',
      'B': 'billion',
      'T': 'trillion',
    };

    return text.replaceAllMapped(
      RegExp(r'([\$€£¥])\s*([\d,]+(?:\.\d+)?)\s*([KMBT])?(?![a-zA-Z\d])'),
      (m) {
        final unit = symbols[m[1]] ?? '';
        final raw = m[2]!.replaceAll(',', '');
        final suffix = m[3];
        if (suffix != null) {
          final num = raw.contains('.')
              ? _floatToWords(raw)
              : numberToWords(int.parse(raw));
          return '$num ${scaleMap[suffix]} ${unit}s';
        }
        if (raw.contains('.')) {
          final parts = raw.split('.');
          final intW = numberToWords(int.parse(parts[0]));
          final decVal = int.parse(parts[1].padRight(2, '0').substring(0, 2));
          var result = '$intW ${unit}s';
          if (decVal > 0) result += ' and ${numberToWords(decVal)} cents';
          return result;
        }
        final val = int.parse(raw);
        return '${numberToWords(val)} $unit${val != 1 ? "s" : ""}';
      },
    );
  }

  String _expandPercentages(String text) {
    return text.replaceAllMapped(RegExp(r'(-?[\d,]+(?:\.\d+)?)\s*%'), (m) {
      final raw = m[1]!.replaceAll(',', '');
      final w = raw.contains('.')
          ? _floatToWords(raw)
          : numberToWords(int.parse(raw));
      return '$w percent';
    });
  }

  String _expandTime(String text) {
    return text.replaceAllMapped(
      RegExp(r'\b(\d{1,2}):(\d{2})\s*(am|pm)?\b', caseSensitive: false),
      (m) {
        final h = int.parse(m[1]!);
        final mins = int.parse(m[2]!);
        final suffix = m[3] != null ? ' ${m[3]!.toLowerCase()}' : '';
        final hWords = numberToWords(h);
        if (mins == 0) {
          return m[3] != null ? '$hWords$suffix' : '$hWords hundred$suffix';
        }
        if (mins < 10) return '$hWords oh ${numberToWords(mins)}$suffix';
        return '$hWords ${numberToWords(mins)}$suffix';
      },
    );
  }

  String _expandOrdinals(String text) {
    return text.replaceAllMapped(
      RegExp(r'\b(\d+)(st|nd|rd|th)\b', caseSensitive: false),
      (m) => _ordinalSuffix(int.parse(m[1]!)),
    );
  }

  String _expandUnits(String text) {
    const unitMap = {
      'km': 'kilometers',
      'kg': 'kilograms',
      'mg': 'milligrams',
      'ml': 'milliliters',
      'gb': 'gigabytes',
      'mb': 'megabytes',
      'kb': 'kilobytes',
      'hz': 'hertz',
      'mph': 'miles per hour',
      'ms': 'milliseconds',
    };
    return text.replaceAllMapped(
      RegExp(
        r'(\d+(?:\.\d+)?)\s*(km|kg|mg|ml|gb|mb|kb|hz|mph|ms)\b',
        caseSensitive: false,
      ),
      (m) {
        final raw = m[1]!;
        final unit = unitMap[m[2]!.toLowerCase()] ?? m[2]!;
        final num = raw.contains('.')
            ? _floatToWords(raw)
            : numberToWords(int.parse(raw));
        return '$num $unit';
      },
    );
  }

  String _expandFractions(String text) {
    return text.replaceAllMapped(RegExp(r'\b(\d+)\s*/\s*(\d+)\b'), (m) {
      final num = int.parse(m[1]!);
      final den = int.parse(m[2]!);
      if (den == 0) return m[0]!;
      final numW = numberToWords(num);
      String denomW;
      if (den == 2) {
        denomW = num == 1 ? 'half' : 'halves';
      } else if (den == 4) {
        denomW = num == 1 ? 'quarter' : 'quarters';
      } else {
        denomW = _ordinalSuffix(den);
        if (num != 1) denomW += 's';
      }
      return '$numW $denomW';
    });
  }

  String _expandPhoneNumbers(String text) {
    String digits(String s) => s
        .split('')
        .map((c) => _ones[int.parse(c)].isEmpty ? 'zero' : _ones[int.parse(c)])
        .join(' ');
    text = text.replaceAllMapped(
      RegExp(r'\b(\d{3})-(\d{3})-(\d{4})\b'),
      (m) => '${digits(m[1]!)} ${digits(m[2]!)} ${digits(m[3]!)}',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(\d{3})-(\d{4})\b'),
      (m) => '${digits(m[1]!)} ${digits(m[2]!)}',
    );
    return text;
  }

  String _expandRanges(String text) {
    return text.replaceAllMapped(
      RegExp(r'(?<!\w)(\d+)-(\d+)(?!\w)'),
      (m) =>
          '${numberToWords(int.parse(m[1]!))} to ${numberToWords(int.parse(m[2]!))}',
    );
  }

  String _expandModelNames(String text) {
    return text.replaceAllMapped(
      RegExp(r'\b([a-zA-Z][a-zA-Z0-9]*)-(\d[\d.]*)(?=[^\d.]|$)'),
      (m) => '${m[1]} ${m[2]}',
    );
  }

  String _replaceNumbers(String text) {
    return text.replaceAllMapped(RegExp(r'(?<![a-zA-Z])-?[\d,]+(?:\.\d+)?'), (
      m,
    ) {
      final raw = m[0]!.replaceAll(',', '');
      try {
        if (raw.contains('.')) return _floatToWords(raw);
        return numberToWords(int.parse(raw));
      } catch (_) {
        return m[0]!;
      }
    });
  }

  String _normalizeWhitespace(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
