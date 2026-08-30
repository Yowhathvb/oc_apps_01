const fs = require('fs');
const file = 'c:/zharfan/project/our-chat/apps/oc_apps_01/lib/services/api_service.dart';
let content = fs.readFileSync(file, 'utf8');

const newMethods = 
  static Future<Map<String, dynamic>> updateCartItemQuantity(String cartId, int quantity) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('\\/marketplace/cart'), 
        headers: headers,
        body: jsonEncode({
          'cartId': cartId,
          'quantity': quantity,
        }),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan sistem'};
    }
  }

  static Future<Map<String, dynamic>> deleteCartItem(String cartId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('\\/marketplace/cart?id=\\'), 
        headers: headers,
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Terjadi kesalahan sistem'};
    }
  }
;

content = content.replace('static Future<Map<String, dynamic>> getCart()', newMethods + '\n  static Future<Map<String, dynamic>> getCart()');
fs.writeFileSync(file, content);
