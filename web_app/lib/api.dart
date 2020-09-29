import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html';

enum LoginStatus {
  loggedIn,
  loggedOut,
}

enum RequestStatus {
  ok,
  failed,
}

LoginStatus decodeLoginStatus(String s) {
  var parsed = jsonDecode(s);
  if (parsed["status"] == "logged_in") {
    return LoginStatus.loggedIn;
  } else {
    return LoginStatus.loggedOut;
  }
}

RequestStatus decodeStatus(String s) {
  var parsed = jsonDecode(s);
  if (parsed["status"] == "ok") {
    return RequestStatus.ok;
  } else {
    return RequestStatus.failed;
  }
}

class CookieManager {
  static addToCookie(String key, String value) {
     document.cookie = "$key=$value; max-age=2592000; path=/;";
  }

  static removeCookie(String key) {
     document.cookie = "$key=0; max-age=0; path=/;";
  }

  static String getCookie(String key) {
    String cookies = document.cookie;
    List<String> listValues = cookies.isNotEmpty ? cookies.split(";") : List();
    String matchVal = "";

    for (int i = 0; i < listValues.length; i++) {
      List<String> map = listValues[i].split("=");
      String _key = map[0].trim();
      String _val = map[1].trim();

      if (key == _key) {
        matchVal = _val;
        break;
      }
    }

    return matchVal;
  }
}

const APIBase = "http://localhost:5000/api/";

class BoulderhausAPI {
  const BoulderhausAPI();

  Future<LoginStatus> loginStatus() {
    var cookies = _getCookies();
    return http.get(APIBase + "status", headers: cookies).then((resp) => decodeLoginStatus(resp.body));
  }

  Map<String,String> _getCookies() {
    var cookies = Map<String, String>();
    var cookieString = "";
    var first = true;

    var usernameCookie = CookieManager.getCookie("username");

    if (usernameCookie != "" && usernameCookie != "0") {
      cookieString += "username=$usernameCookie";
      cookies["X-Username"] = usernameCookie;
      first = false;
    }

    var tokenCookie = CookieManager.getCookie("token");

    if (tokenCookie != "" && tokenCookie != "0") {
      if (!first) {
        cookieString += "; ";
      }
      cookieString += "token=$tokenCookie";
      cookies["X-Token"] = tokenCookie;
    }

    if (cookieString != "") {
      cookies["Cookie"] = cookieString;
    }

    return cookies;
  }

  Future<RequestStatus> login(username, password) {
    var cookies = _getCookies();

    Map<String,String> headers = {
      'Content-type' : 'application/json',
      'Accept': 'application/json',
      ...cookies
    };

    Map<String,String> body = {
      'username': username,
      'password': password,
    };

    return http.post(APIBase + 'login', headers: headers, body: jsonEncode(body)).then((resp) {
        for (var header in resp.headers.entries) {
          if (header.key == "x-token") {
            CookieManager.addToCookie("token", header.value);
          }

          if (header.key == "x-username") {
            CookieManager.addToCookie("username", header.value);
          }
        }

        return decodeStatus(resp.body);
    });
  }

  Future<RequestStatus> createUser(username, password, info) {
    Map<String,String> headers = {
      'Content-type' : 'application/json',
      'Accept': 'application/json',
    };

    Map<String,dynamic> body = {
      'username': username,
      'password': password,
      'info': info,
    };

    return http.post(APIBase + 'create_user', headers: headers, body: jsonEncode(body)).then((resp) {
        for (var header in resp.headers.entries) {
          if (header.key == "x-token") {
            CookieManager.addToCookie("token", header.value);
          }

          if (header.key == "x-username") {
            CookieManager.addToCookie("username", header.value);
          }
        }

        return decodeStatus(resp.body);
      });
  }

  Future<List<dynamic>> slots(DateTime date) {
    Map<String,String> headers = {
      'Content-type' : 'application/json',
      'Accept': 'application/json',
    };

    Map<String,dynamic> body = {
      'date': date.toIso8601String().substring(0, 10),
    };
    return http.post(APIBase + "list_slots", headers: headers, body: jsonEncode(body)).then((resp) => jsonDecode(resp.body));
  }

  Future<RequestStatus> bookSlot(slot) {
    var cookies = _getCookies();

    Map<String,String> headers = {
      'Content-type' : 'application/json',
      'Accept': 'application/json',
      ...cookies
    };

    Map<String,String> body = {
      'slot': slot,
    };

    return http.post(APIBase + 'book_slot', headers: headers, body: jsonEncode(body)).then((resp) {
        return decodeStatus(resp.body);
    });
  }

  Future<Map<String, dynamic>> userInfo() {
    var cookies = _getCookies();

    Map<String,String> headers = {
      'Content-type' : 'application/json',
      'Accept': 'application/json',
      ...cookies
    };

    return http.get(APIBase + 'user_info', headers: headers).then((resp) {
        return jsonDecode(resp.body);
    });
  }

  Future<RequestStatus> modifyUser(info) {
    var cookies = _getCookies();

    Map<String,String> headers = {
      'Content-type' : 'application/json',
      'Accept': 'application/json',
      ...cookies
    };

    return http.post(APIBase + 'user_info', headers: headers, body: jsonEncode(info)).then((resp) {
        return decodeStatus(resp.body);
    });
  }

  Future<RequestStatus> logout() {
    CookieManager.removeCookie("username");
    CookieManager.removeCookie("token");

    Map<String,String> headers = {
      'Content-type' : 'application/json',
      'Accept': 'application/json',
    };

    return http.get(APIBase + 'logout', headers: headers).then((resp) {
        return decodeStatus(resp.body);
    });
  }
}
