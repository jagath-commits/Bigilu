import 'dart:convert';

void main() {
  var post1 = {'content': '{" pages\: [], \category\: \Manu\}'};
 var content = post1['content'];
 dynamic decoded;
 if (content is String) {
 decoded = jsonDecode(content);
 }
 print(decoded['category'] == 'Manu');
}
