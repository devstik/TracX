import 'package:flutter/material.dart';
// Import necessário para a configuração de localização
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/registro.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      title: 'TraceX',
      debugShowCheckedModeBanner: false,

      // >>> CONFIGURAÇÃO ESSENCIAL DE LOCALIZAÇÃO (pt_BR) <<<
      localizationsDelegates: const [
        // Delega o suporte a textos do Material Design (essencial para o DatePicker)
        GlobalMaterialLocalizations.delegate,
        // Delega o suporte a layouts (ordem da escrita)
        GlobalWidgetsLocalizations.delegate,
        // Delega o suporte a componentes do estilo Cupertino (iOS)
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''), // Inglês
        Locale(
          'pt',
          'BR',
        ), // Português do Brasil (necessário para o DatePicker)
      ],
      // Define o idioma padrão da aplicação para o português
      locale: const Locale('pt', 'BR'),

      // FIM DA CONFIGURAÇÃO DE LOCALIZAÇÃO
      home: SplashScreen(),
    );
  }
}
