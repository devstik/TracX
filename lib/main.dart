import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
// Import necessário para a configuração de localização
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models/registro.dart';
import 'screens/splash_screen.dart';

import 'services/datawedge_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 🔵 INICIALIZA O DATAWEDGE ANTES DE ABRIR O APP
  DataWedgeService.init();

  await Hive.initFlutter();
  Hive.registerAdapter(RegistroAdapter());
  await Hive.openBox<int>('lastIdBox');
  await Hive.openBox<Registro>('registros');

  // 💡 Box para armazenar usuários e senhas (mantido)
  await Hive.openBox<String>('user_data');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TracX',
      debugShowCheckedModeBanner: false,

      // >>> CONFIGURAÇÃO ESSENCIAL DE LOCALIZAÇÃO (pt_BR) <<<
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''),
        Locale('pt', 'BR'), // <<< Necessário para datas PT-BR
      ],
      locale: const Locale('pt', 'BR'),

      // FIM DA CONFIGURAÇÃO DE LOCALIZAÇÃO
      home: SplashScreen(),
    );
  }
}
