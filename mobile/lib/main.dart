import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiUrl = String.fromEnvironment('RIOGRAM_API_URL',
    defaultValue: 'https://riogram-api-r26.onrender.com');

void main() => runApp(const RiogramApp());

class RiogramApp extends StatefulWidget {
  const RiogramApp({super.key});
  @override
  State<RiogramApp> createState() => _RiogramAppState();
}

class _RiogramAppState extends State<RiogramApp> {
  ThemeMode mode = ThemeMode.system;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Riogram',
    debugShowCheckedModeBanner: false,
    themeMode: mode,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2879CF)),
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF5F7FA)),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF69A8F5), brightness: Brightness.dark),
    ),
    home: RiogramHome(onThemeChange: (value) => setState(() => mode = value), themeMode: mode),
  );
}

class DemoChat {
  final String name, message, time;
  final Color color;
  final int unread;
  const DemoChat(this.name, this.message, this.time, this.color, this.unread);
}

const demoChats = <DemoChat>[
  DemoChat('Александр', 'Привет! Как твои дела?', '12:45', Color(0xFF4389C7), 2),
  DemoChat('Семья', 'Увидимся вечером 😊', '11:20', Color(0xFF8C65BF), 0),
  DemoChat('Мария', 'Спасибо, договорились!', 'Вчера', Color(0xFF36A389), 0),
  DemoChat('Рабочая группа', 'Документы отправлены', 'Пн', Color(0xFFD18C46), 5),
];

class RiogramHome extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChange;
  final ThemeMode themeMode;
  const RiogramHome({super.key, required this.onThemeChange, required this.themeMode});
  @override
  State<RiogramHome> createState() => _RiogramHomeState();
}

class _RiogramHomeState extends State<RiogramHome> {
  int selected = 0;
  String search = '';
  bool serverOk = false;
  bool checkedServer = false;
  static const titles = ['Чаты', 'Контакты', 'Звонки', 'Настройки'];
  static const icons = [Icons.forum_outlined, Icons.contacts_outlined,
    Icons.call_outlined, Icons.settings_outlined];

  @override
  void initState() {
    super.initState();
    checkServer();
  }

  Future<void> checkServer() async {
    try {
      final response = await http.get(Uri.parse(apiUrl + '/api/v1/health'))
        .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (mounted) setState(() {
        checkedServer = true;
        serverOk = response.statusCode == 200 && data['status'] == 'ok';
      });
    } catch (_) {
      if (mounted) setState(() { checkedServer = true; serverOk = false; });
    }
  }

  void showUnavailable(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(feature + ': потребуется регистрация и подключение сервера.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Riogram', style: TextStyle(
          fontWeight: FontWeight.w800, color: cs.primary, letterSpacing: -0.6)),
        actions: [
          IconButton(
            tooltip: 'Проверить сервер',
            icon: Icon(serverOk ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              color: serverOk ? Colors.green : cs.onSurfaceVariant),
            onPressed: checkServer,
          ),
          IconButton(
            tooltip: 'Профиль',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const ProfilePage())),
          ),
        ],
      ),
      body: SafeArea(child: switch (selected) {
        0 => chatsPage(),
        1 => contactsPage(),
        2 => callsPage(),
        _ => settingsPage(),
      }),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) => setState(() { selected = index; search = ''; }),
        destinations: [
          for (var i = 0; i < titles.length; i++)
            NavigationDestination(icon: Icon(icons[i]), label: titles[i]),
        ],
      ),
      floatingActionButton: selected == 0 ? FloatingActionButton(
        onPressed: () => setState(() => selected = 1),
        tooltip: 'Новый чат',
        child: const Icon(Icons.edit_square),
      ) : null,
    );
  }

  Widget demoNotice() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(children: [
      Icon(Icons.info_outline, size: 20),
      SizedBox(width: 10),
      Expanded(child: Text('Демо-интерфейс: контакты и сообщения ниже — примеры.')),
    ]),
  );

  Widget searchBox(String hint) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: TextField(
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: hint,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none),
      ),
      onChanged: (value) => setState(() => search = value),
    ),
  );

  Widget chatsPage() {
    final filtered = demoChats.where((chat) =>
      chat.name.toLowerCase().contains(search.toLowerCase())).toList();
    return Column(children: [
      searchBox('Поиск по чатам'),
      demoNotice(),
      Expanded(child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 82),
        itemBuilder: (context, i) {
          final chat = filtered[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            leading: CircleAvatar(
              radius: 27, backgroundColor: chat.color,
              child: Text(chat.name.substring(0, 1),
                style: const TextStyle(color: Colors.white, fontSize: 23)),
            ),
            title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(chat.time, style: Theme.of(context).textTheme.labelSmall),
              if (chat.unread > 0) ...[
                const SizedBox(height: 5),
                CircleAvatar(radius: 11, backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(chat.unread.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 11))),
              ],
            ]),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ConversationPage(chat: chat))),
          );
        },
      )),
    ]);
  }

  Widget contactsPage() => Column(children: [
    searchBox('Найти контакт'),
    demoNotice(),
    ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_add_alt)),
      title: const Text('Синхронизировать контакты'),
      subtitle: const Text('Разрешение и подключение к API будут добавлены'),
      onTap: () => showUnavailable('Синхронизация контактов'),
    ),
    Expanded(child: ListView(
      children: demoChats.where((c) =>
        c.name.toLowerCase().contains(search.toLowerCase())).map((c) => ListTile(
          leading: CircleAvatar(backgroundColor: c.color,
            child: Text(c.name.substring(0, 1), style: const TextStyle(color: Colors.white))),
          title: Text(c.name),
          trailing: const Icon(Icons.chat_bubble_outline),
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ConversationPage(chat: c))),
        )).toList(),
    )),
  ]);

  Widget callsPage() => Column(children: [
    demoNotice(),
    const SizedBox(height: 24),
    Icon(Icons.video_call_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 16),
    Text('Голосовые и видеозвонки', style: Theme.of(context).textTheme.titleLarge),
    const Padding(padding: EdgeInsets.all(20),
      child: Text('Экран звонков подготовлен. WebRTC и звонки между телефонами ещё не подключены.',
        textAlign: TextAlign.center)),
    FilledButton.icon(
      onPressed: () => showUnavailable('Звонки'),
      icon: const Icon(Icons.add_call),
      label: const Text('Новый звонок'),
    ),
  ]);

  Widget settingsPage() => ListView(children: [
    ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Тема оформления'),
      trailing: DropdownButton<ThemeMode>(
        value: widget.themeMode,
        onChanged: (value) { if (value != null) widget.onThemeChange(value); },
        items: const [
          DropdownMenuItem(value: ThemeMode.system, child: Text('Системная')),
          DropdownMenuItem(value: ThemeMode.light, child: Text('Светлая')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Тёмная')),
        ],
      ),
    ),
    const Divider(),
    ListTile(
      leading: Icon(serverOk ? Icons.cloud_done : Icons.cloud_off),
      title: const Text('Состояние сервера'),
      subtitle: Text(!checkedServer ? 'Проверяем…' : serverOk ? 'API доступен' : 'API недоступен'),
      trailing: const Icon(Icons.refresh),
      onTap: checkServer,
    ),
    ListTile(
      leading: const Icon(Icons.lock_outline),
      title: const Text('Безопасность'),
      subtitle: const Text('Регистрация и защита сессий — в разработке'),
      onTap: () => showUnavailable('Безопасность'),
    ),
    const ListTile(
      leading: Icon(Icons.info_outline),
      title: Text('Riogram · версия 0.4.0'),
      subtitle: Text('Тестовая версия. Не предназначена для реальной переписки.'),
    ),
  ]);
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Профиль')),
    body: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(radius: 42, child: Icon(Icons.person_outline, size: 48)),
      SizedBox(height: 16),
      Text('Вход по номеру телефона', style: TextStyle(fontSize: 20)),
      SizedBox(height: 8),
      Padding(padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text('SMS-подтверждение пока не подключено.',
          textAlign: TextAlign.center)),
    ])),
  );
}

class ConversationPage extends StatefulWidget {
  final DemoChat chat;
  const ConversationPage({super.key, required this.chat});
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}
class _ConversationPageState extends State<ConversationPage> {
  final controller = TextEditingController();
  final List<String> draftMessages = [];
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.chat.name),
      actions: [
        IconButton(icon: const Icon(Icons.call_outlined),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Звонки пока не подключены')))),
        IconButton(icon: const Icon(Icons.videocam_outlined),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Видеозвонки пока не подключены')))),
      ],
    ),
    body: Column(children: [
      const Padding(padding: EdgeInsets.all(8),
        child: Text('Демо: сообщения не отправляются на сервер')),
      Expanded(child: ListView(children: [
        for (final text in [widget.chat.message, ...draftMessages])
          Align(
            alignment: draftMessages.contains(text) ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16)),
              child: Text(text),
            ),
          ),
      ])),
      SafeArea(child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Expanded(child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Демо-сообщение',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
            ),
          )),
          IconButton.filled(
            icon: const Icon(Icons.send),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              setState(() => draftMessages.add(text));
              controller.clear();
            },
          ),
        ]),
      )),
    ]),
  );
}
