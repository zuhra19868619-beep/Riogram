import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const serverUrl = String.fromEnvironment('RIOGRAM_API_URL', defaultValue: 'https://riogram-api-r26.onrender.com');

class ApiClient {
  String? token;
  Future<dynamic> request(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$serverUrl/api/v1$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final response = await http.Request(method, uri).sendWithBody(headers, body);
    dynamic data;
    try { data = jsonDecode(response.body); } catch (_) { data = response.body; }
    if (response.statusCode >= 400) {
      throw Exception(data is Map ? (data['detail'] ?? response.statusCode).toString() : 'HTTP ${response.statusCode}');
    }
    return data;
  }
}

extension _RequestBody on http.Request {
  Future<http.Response> sendWithBody(Map<String, String> headers, Map<String, dynamic>? body) async {
    this.headers.addAll(headers);
    if (body != null) this.body = jsonEncode(body);
    return http.Response.fromStream(await send());
  }
}

class ConnectedApp extends StatefulWidget {
  const ConnectedApp({super.key});
  @override
  State<ConnectedApp> createState() => _ConnectedAppState();
}

class _ConnectedAppState extends State<ConnectedApp> {
  final api = ApiClient();
  final phone = TextEditingController();
  final code = TextEditingController();
  bool requested = false, busy = false;
  String? error;
  String? userId;
  @override
  void dispose() { phone.dispose(); code.dispose(); super.dispose(); }

  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      if (!requested) {
        await api.request('POST', '/auth/request-code', {'phone_number': phone.text.trim()});
        if (mounted) setState(() => requested = true);
      } else {
        final result = await api.request('POST', '/auth/verify-code',
            {'phone_number': phone.text.trim(), 'code': code.text.trim()});
        api.token = result['access_token'] as String;
        if (mounted) setState(() => userId = result['user_id'] as String);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (userId != null) return RealChats(api: api, userId: userId!, onLogout: () {
      setState(() { api.token = null; userId = null; requested = false; code.clear(); });
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Riogram — вход')),
      body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
          const Icon(Icons.forum_rounded, size: 76),
          const SizedBox(height: 18),
          Text('Войти по номеру телефона', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          TextField(controller: phone, enabled: !requested && !busy,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Телефон +998...', border: OutlineInputBorder())),
          if (requested) ...[
            const SizedBox(height: 14),
            TextField(controller: code, enabled: !busy, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Код из SMS', border: OutlineInputBorder())),
          ],
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 18),
          FilledButton(onPressed: busy ? null : submit,
            child: Text(busy ? 'Подождите…' : requested ? 'Подтвердить код' : 'Получить код')),
          if (requested) TextButton(onPressed: busy ? null : () => setState(() => requested = false),
            child: const Text('Изменить номер')),
          const SizedBox(height: 20),
          const Text('Для настоящего SMS требуется настройка Twilio на сервере. Демо-коды не принимаются.',
            textAlign: TextAlign.center),
        ]),
      )),
    );
  }
}

class RealChats extends StatefulWidget {
  final ApiClient api;
  final String userId;
  final VoidCallback onLogout;
  const RealChats({super.key, required this.api, required this.userId, required this.onLogout});
  @override
  State<RealChats> createState() => _RealChatsState();
}
class _RealChatsState extends State<RealChats> {
  List<dynamic> chats = [];
  String? error;
  bool loading = true;
  @override
  void initState() { super.initState(); reload(); }
  Future<void> reload() async {
    try {
      final data = await widget.api.request('GET', '/chats');
      if (mounted) setState(() { chats = data as List; error = null; loading = false; });
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    }
  }
  Future<void> findContact() async {
    final input = TextEditingController();
    final phone = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Поиск контакта'),
      content: TextField(controller: input, keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Телефон в формате +998…')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, input.text.trim()), child: const Text('Найти')),
      ],
    ));
    input.dispose();
    if (phone == null || phone.isEmpty) return;
    try {
      final result = await widget.api.request('POST', '/contacts/match', {'phones': [phone]});
      final contacts = result['contacts'] as List;
      if (!mounted) return;
      if (contacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Контакт пока не зарегистрирован')));
        return;
      }
      final recipientId = contacts.first['id'] as String;
      final chat = await widget.api.request('POST', '/chats/direct', {'recipient_id': recipientId});
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        RealConversation(api: widget.api, chatId: chat['id'] as String, userId: widget.userId)));
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> newChat() async {
    final input = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Новый чат'),
      content: TextField(controller: input, decoration: const InputDecoration(
        labelText: 'ID пользователя', helperText: 'UUID зарегистрированного пользователя')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, input.text.trim()), child: const Text('Создать')),
      ],
    ));
    input.dispose();
    if (result == null || result.isEmpty) return;
    try {
      final chat = await widget.api.request('POST', '/chats/direct', {'recipient_id': result});
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        RealConversation(api: widget.api, chatId: chat['id'] as String, userId: widget.userId)));
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Riogram — чаты'), actions: [
      IconButton(onPressed: findContact, icon: const Icon(Icons.person_search), tooltip: 'Найти контакт'),
      IconButton(onPressed: reload, icon: const Icon(Icons.refresh), tooltip: 'Обновить'),
      IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout), tooltip: 'Выйти'),
    ]),
    floatingActionButton: FloatingActionButton(onPressed: newChat, child: const Icon(Icons.add_comment_outlined)),
    body: loading ? const Center(child: CircularProgressIndicator()) :
      error != null ? Center(child: Text(error!)) :
      RefreshIndicator(onRefresh: reload, child: ListView(
        children: [
          ListTile(title: const Text('Ваш ID'), subtitle: SelectableText(widget.userId)),
          if (chats.isEmpty) const ListTile(title: Text('Пока нет чатов'),
            subtitle: Text('Нажмите +, чтобы создать переписку')),
          for (final chat in chats) ListTile(
            leading: const CircleAvatar(child: Icon(Icons.chat_bubble_outline)),
            title: Text(chat['title']?.toString() ?? (chat['type'] == 'group' ? 'Группа' : 'Личный чат')),
            subtitle: Text(chat['id'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => RealConversation(
                api: widget.api, chatId: chat['id'] as String, userId: widget.userId)));
              reload();
            },
          ),
        ],
      )),
  );
}

class RealConversation extends StatefulWidget {
  final ApiClient api;
  final String chatId, userId;
  const RealConversation({super.key, required this.api, required this.chatId, required this.userId});
  @override
  State<RealConversation> createState() => _RealConversationState();
}
class _RealConversationState extends State<RealConversation> {
  final input = TextEditingController();
  List<dynamic> messages = [];
  String? error;
  bool sending = false;
  @override
  void initState() { super.initState(); reload(); }
  @override
  void dispose() { input.dispose(); super.dispose(); }
  Future<void> reload() async {
    try {
      final result = await widget.api.request('GET', '/chats/${widget.chatId}/messages');
      if (mounted) setState(() { messages = result as List; error = null; });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
  }
  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await widget.api.request('POST', '/chats/${widget.chatId}/messages', {
        'client_message_id': DateTime.now().microsecondsSinceEpoch.toString(),
        'text': text,
      });
      input.clear();
      await reload();
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => sending = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Переписка'), actions: [
      IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
    ]),
    body: Column(children: [
      if (error != null) Padding(padding: const EdgeInsets.all(8),
        child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Expanded(child: RefreshIndicator(onRefresh: reload, child: ListView(
        children: [
          for (final msg in messages) Align(
            alignment: msg['sender_id'] == widget.userId ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14)),
              child: Text(msg['text'].toString()),
            ),
          ),
        ],
      ))),
      SafeArea(child: Padding(padding: const EdgeInsets.all(10),
        child: Row(children: [
          Expanded(child: TextField(controller: input, onSubmitted: (_) => send(),
            decoration: const InputDecoration(hintText: 'Сообщение…', border: OutlineInputBorder()))),
          IconButton.filled(onPressed: sending ? null : send, icon: const Icon(Icons.send)),
        ]),
      )),
    ]),
  );
}
