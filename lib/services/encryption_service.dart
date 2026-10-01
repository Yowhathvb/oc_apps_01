import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  // CATATAN: Untuk E2EE yang sesungguhnya (Signal Protocol), key ini didapatkan 
  // dari pertukaran kunci (Diffie-Hellman) antar pengguna.
  // Untuk contoh AES-256 sederhana, kita gunakan static key 32 karakter.
  static final _key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1'); 
  
  // IV (Initialization Vector) 16 karakter
  static final _iv = encrypt.IV.fromUtf8('my16lengthsecrIV');

  /// Fungsi untuk mengubah Plain text -> Ciphertext (Teks Acak)
  static String encryptMessage(String plainText) {
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: _iv);
      return encrypted.base64; // Hasilnya berupa string acak (Base64)
    } catch (e) {
      return plainText; // Fallback jika gagal
    }
  }

  /// Fungsi untuk mengubah Ciphertext -> Plain text kembali
  static String decryptMessage(String cipherTextBase64) {
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
      final decrypted = encrypter.decrypt64(cipherTextBase64, iv: _iv);
      return decrypted;
    } catch (e) {
      // Jika bukan base64 AES yang valid, kembalikan teks aslinya
      // Ini berguna agar pesan lama (plain text) tetap bisa terbaca.
      return cipherTextBase64; 
    }
  }
}
