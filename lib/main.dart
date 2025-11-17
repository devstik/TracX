import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/registro.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(RegistroAdapter());
  await Hive.openBox<int>('lastIdBox');
  await Hive.openBox<Registro>('registros');

  // 💡 Nova linha adicionada para armazenar usuários e senhas
  await Hive.openBox<String>('user_data');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TraceX',
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}
