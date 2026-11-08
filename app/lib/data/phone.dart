/// Turns an Egyptian mobile number as people type it (010..., +20 10...,
/// 0020..., or with Arabic digits) into E.164 (+2010xxxxxxxx). Returns null
/// if it isn't an Egyptian mobile number.
String? normalizeEgyptianMobile(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < arabic.length; i++) {
    input = input.replaceAll(arabic[i], '$i');
  }
  var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('0020')) digits = digits.substring(4);
  if (digits.startsWith('20') && digits.length == 12) digits = digits.substring(2);
  if (digits.startsWith('1') && digits.length == 10) digits = '0$digits';
  if (!RegExp(r'^01[0125][0-9]{8}$').hasMatch(digits)) return null;
  return '+2$digits';
}
