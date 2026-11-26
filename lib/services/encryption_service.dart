import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  // Kunci AES-256 (32 karakter UTF-8 = 256-bit)
  static final _key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1'); 
  
  // IV (Initialization Vector) 16 karakter UTF-8 = 128-bit
  static final _iv = encrypt.IV.fromUtf8('my16lengthsecrIV');

  /// Fungsi untuk mengubah Plain text -> Ciphertext (Teks Acak Base64)
  static String encryptMessage(String plainText) {
    if (plainText.isEmpty) return plainText;
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64; // Hasilnya string acak Base64 (misal: wH77rydOUpiG9yPlKkcgIw==)
    } catch (e) {
      print('Encryption error: $e');
      return plainText; // Fallback jika gagal
    }
  }

  /// Fungsi untuk mengubah Ciphertext (Base64) -> Plain text kembali
  static String decryptMessage(String cipherTextBase64) {
    if (cipherTextBase64.isEmpty) return cipherTextBase64;
    try {
      String cleanCipher = cipherTextBase64.trim();
      if (cleanCipher.startsWith('enc:')) {
        cleanCipher = cleanCipher.substring(4);
      }
      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
      final decrypted = encrypter.decrypt64(cleanCipher, iv: _iv);
      return decrypted;
    } catch (e) {
      // Jika bukan format AES Base64 yang valid, kembalikan teks aslinya.
      // Ini memastikan riwayat pesan lama (plain text) tetap terbaca normal tanpa error.
      return cipherTextBase64; 
    }
  }

  /// Cek apakah teks merupakan teks terenkripsi yang valid
  static bool isEncrypted(String text) {
    if (text.isEmpty) return false;
    try {
      String clean = text.trim();
      if (clean.startsWith('enc:')) clean = clean.substring(4);
      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
      encrypter.decrypt64(clean, iv: _iv);
      return true;
    } catch (_) {
      return false;
    }
  }
}
