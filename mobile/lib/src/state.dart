import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

enum Mode { driver, host, admin }

class AppState extends ChangeNotifier {
  final api = Api();
  Json? user;
  Mode mode = Mode.driver;
  List<Json> vehicles = [];
  String? vehicleId;
  bool ready = false;

  bool get isHost => user?['isHost'] == true;
  bool get isAdmin => user?['isAdmin'] == true;
  Json? get vehicle => vehicles.where((v) => v['id'] == vehicleId).firstOrNull ?? vehicles.firstOrNull;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString('token');
    if (t != null) {
      api.token = t;
      try {
        await _adopt(await api.get('/auth/me'));
        if (isAdmin) mode = Mode.admin;
      } catch (_) {
        api.token = null;
        await prefs.remove('token');
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _adopt(dynamic res) async {
    api.token = res['token'];
    user = Map<String, dynamic>.from(res['user']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', api.token!);
    if (mode == Mode.admin && !isAdmin) mode = Mode.driver;
    if (mode == Mode.host && !isHost) mode = Mode.driver;
    await loadVehicles();
  }

  Future<void> login(String email, String password) async {
    await _adopt(await api.post('/auth/login', {'email': email, 'password': password}));
    mode = isAdmin ? Mode.admin : Mode.driver;
    notifyListeners();
  }

  Future<void> register(String name, String email, String password, bool host) async {
    await _adopt(await api.post('/auth/register', {'name': name, 'email': email, 'password': password, 'isHost': host}));
    mode = host ? Mode.host : Mode.driver;
    notifyListeners();
  }

  Future<void> becomeHost() async {
    await _adopt(await api.post('/me/become-host'));
    mode = Mode.host;
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    api.token = null;
    user = null;
    vehicles = [];
    mode = Mode.driver;
    notifyListeners();
  }

  void setMode(Mode m) {
    mode = m;
    notifyListeners();
  }

  Future<void> loadVehicles() async {
    final list = await api.get('/me/vehicles') as List;
    vehicles = list.map((e) => Map<String, dynamic>.from(e)).toList();
    notifyListeners();
  }

  void selectVehicle(String id) {
    vehicleId = id;
    notifyListeners();
  }
}
