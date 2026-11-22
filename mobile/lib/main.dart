import 'package:flutter/material.dart';

void main() => runApp(const RiogramApp());

class RiogramApp extends StatelessWidget {
  const RiogramApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Riogram',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2679C9)), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2679C9), brightness: Brightness.dark), useMaterial3: true),
      home: const RiogramHome(),
    );
  }
}

class RiogramHome extends StatefulWidget {
  const RiogramHome({super.key});
  @override
  State<RiogramHome> createState() => _RiogramHomeState();
}

class _RiogramHomeState extends State<RiogramHome> {
  int selected = 0;
  static const labels = ['Чаты', 'Контакты', 'Профиль', 'Настройки'];
  static const icons = [Icons.chat_bubble_outline, Icons.contacts_outlined, Icons.person_outline, Icons.settings_outlined];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Riogram · ${labels[selected]}')),
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icons[selected], size: 64, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 12),
      Text(labels[selected], style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Подключение к серверу и реальные данные — следующий этап.'),
    ])),
    bottomNavigationBar: NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (value) => setState(() => selected = value),
      destinations: [for (var i = 0; i < labels.length; i++) NavigationDestination(icon: Icon(icons[i]), label: labels[i])],
    ),
  );
}
