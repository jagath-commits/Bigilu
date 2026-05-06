import 'package:http/http.dart' as http;

void main() async {
  try {
    var response = await http.get(Uri.parse('https://bigiluu.com/api/posts/myPosts/USR1802')); // some user ID
    print(response.body.length > 500 ? response.body.substring(0, 500) : response.body);
  } catch (e) { print(e); }
}
