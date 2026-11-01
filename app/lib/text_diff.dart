/// Hasil perbandingan isi kotak ketik sebelum dan sesudah diubah keyboard HP.
class TextEdit {
  const TextEdit(this.backspaces, this.inserted);

  final int backspaces;
  final String inserted;
}

/// Keyboard Android mengirim seluruh isi kotak, bukan tombol per tombol.
/// Selisihnya diubah menjadi Backspace dan teks baru untuk dikirim ke laptop.
TextEdit diffText(String before, String after) {
  var common = 0;
  final limit = before.length < after.length ? before.length : after.length;
  while (common < limit &&
      before.codeUnitAt(common) == after.codeUnitAt(common)) {
    common++;
  }
  return TextEdit(before.length - common, after.substring(common));
}
