// lib/src/text/line_separator.dart

enum LineSeparator {
  lf('\n'),
  crlf('\r\n'),
  cr('\r');

  final String value;
  const LineSeparator(this.value);

  static LineSeparator detect(String text) {
    if (text.contains('\r\n')) return LineSeparator.crlf;
    if (text.contains('\r')) return LineSeparator.cr;
    return LineSeparator.lf;
  }
}
