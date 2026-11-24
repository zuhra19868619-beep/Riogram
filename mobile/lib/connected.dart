import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  String? verificationId;
  int? resendToken;

  Future<void> finishFirebaseLogin(UserCredential credential) async {
    final firebaseUser = credential.user;
    if (firebaseUser == null) throw StateError('Firebase не вернул пользователя');
    final idToken = await firebaseUser.getIdToken(true);
    if (idToken == null) throw StateError('Firebase не выдал токен');
    final result = await api.request('POST', '/auth/firebase-login',
        {'id_token': idToken});
    api.token = result['access_token'] as String;
    if (mounted) setState(() => userId = result['user_id'] as String);
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      if (!requested) {
        final number = phone.text.replaceAll(RegExp(r'[^+0-9]'), '');
        if (!RegExp(r'^\+[1-9][0-9]{7,14}).hasMatch(number)) {
          throw FormatException('Введите номер в международном формате: +998901234567');
        }
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: number,
          forceResendingToken: resendToken,
          verificationCompleted: (credential) async {
            try {
              final signedIn = await FirebaseAuth.instance.signInWithCredential(credential);
              await finishFirebaseLogin(signedIn);
            } catch (e) {
              if (mounted) setState(() { error = e.toString(); busy = false; });
            }
          },
          verificationFailed: (exception) {
            if (mounted) setState(() { error = exception.message ?? exception.code; busy = false; });
          },
          codeSent: (id, token) {
            if (mounted) setState(() {
              verificationId = id;
              resendToken = token;
              requested = true;
              busy = false;
            });
          },
          codeAutoRetrievalTimeout: (id) { verificationId = id; },
          timeout: const Duration(seconds: 60),
        );
      } else {
        if (verificationId == null) throw StateError('Запросите SMS-код заново');
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId!, smsCode: code.text.trim());
        final signedIn = await FirebaseAuth.instance.signInWithCredential(credential);
        await finishFirebaseLogin(signedIn);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted && (requested || error != null)) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (userId != null) return RealChats(api: api, userId: userId!, onLogout: () {
      FirebaseAuth.instance.signOut();
      setState(() { api.token = null; userId = null; requested = false; verificationId = null; code.clear(); });
    });
    return Scaffold(
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30), children: [
          Center(child: Container(width: 108, height: 108,
            decoration: const BoxDecoration(color: Color(0xFF3390EC), shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 55))),
          const SizedBox(height: 30),
          Text(requested ? 'Подтверждение номера' : 'Ваш номер телефона',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 12),
          Text(requested
              ? 'Введите код из SMS, отправленный на ${phone.text.trim()}'
              : 'Пожалуйста, подтвердите код страны и введите номер телефона.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 34),
          if (!requested) TextField(
            key: const Key('phone-input'), controller: phone, enabled: !busy,
            keyboardType: TextInputType.phone, autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Номер телефона', hintText: '+998 90 123 45 67',
              prefixIcon: Icon(Icons.phone_outlined))),
          if (requested) TextField(
            key: const Key('sms-code-input'), controller: code, enabled: !busy,
            autofocus: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Код подтверждения',
              prefixIcon: Icon(Icons.lock_outline))),
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(error!, textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          SizedBox(height: 52, child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3390EC)),
            onPressed: busy ? null : submit,
            child: busy ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(requested ? 'ВОЙТИ' : 'ПРОДОЛЖИТЬ',
                style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          )),
          if (requested) TextButton(onPressed: busy ? null : () =>
            setState(() { requested = false; code.clear(); error = null; }),
            child: const Text('Изменить номер телефона')),
          const SizedBox(height: 26),
          Text('SMS-код отправляется через Firebase Authentication.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ))),
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
  Future<void> newGroup() async {
    final title = TextEditingController();
    final members = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Создать группу'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Название группы')),
        TextField(controller: members, decoration: const InputDecoration(
          labelText: 'ID участников через запятую', helperText: 'UUID пользователей')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Создать')),
      ],
    ));
    final groupTitle = title.text.trim();
    final ids = members.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    title.dispose();
    members.dispose();
    if (result != true || groupTitle.isEmpty || ids.isEmpty) return;
    try {
      final group = await widget.api.request('POST', '/groups', {'title': groupTitle, 'member_ids': ids});
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        RealConversation(api: widget.api, chatId: group['id'] as String, userId: widget.userId)));
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
      IconButton(onPressed: newGroup, icon: const Icon(Icons.group_add_outlined), tooltip: 'Создать группу'),
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
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;
  @override
  void initState() { super.initState(); reload(); connectRealtime(); }
  void connectRealtime() {
    final token = widget.api.token;
    if (token == null) return;
    try {
      final uri = Uri.parse(serverUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://') + '/api/v1/ws');
      channel = WebSocketChannel.connect(uri);
      channel!.sink.add(jsonEncode({'token': token}));
      subscription = channel!.stream.listen((event) {
        try {
          final data = jsonDecode(event as String);
          if (data is Map && data['type'] == 'message' && data['data']?['chat_id'] == widget.chatId) reload();
        } catch (_) {}
      }, onError: (_) {}, cancelOnError: true);
    } catch (_) {}
  }
  @override
  void dispose() { subscription?.cancel(); channel?.sink.close(); input.dispose(); super.dispose(); }
  Future<void> reload() async {
    try {
      final result = await widget.api.request('GET', '/chats/${widget.chatId}/messages');
      if (mounted) setState(() { messages = result as List; error = null; });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
  }
  Future<void> messageActions(Map<String, dynamic> message) async {
    if (message['sender_id'] != widget.userId) return;
    final action = await showModalBottomSheet<String>(context: context, builder: (context) =>
      SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Редактировать'),
          onTap: () => Navigator.pop(context, 'edit')),
        ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Удалить'),
          onTap: () => Navigator.pop(context, 'delete')),
      ])));
    if (action == null) return;
    try {
      if (action == 'delete') {
        await widget.api.request('DELETE', '/messages/${message['id']}');
      } else {
        final editController = TextEditingController(text: message['text'].toString());
        final newText = await showDialog<String>(context: context, builder: (context) =>
          AlertDialog(title: const Text('Изменить сообщение'),
            content: TextField(controller: editController, autofocus: true, maxLines: 3),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(context, editController.text.trim()),
                child: const Text('Сохранить')),
            ]));
        editController.dispose();
        if (newText == null || newText.isEmpty) return;
        await widget.api.request('PATCH', '/messages/${message['id']}', {'text': newText});
      }
      await reload();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
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
            child: GestureDetector(
              onLongPress: () => messageActions(Map<String, dynamic>.from(msg as Map)),
              child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14)),
              child: Text(msg['text'].toString()),
            )),
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
).hasMatch(number)) {
          throw FormatException('Введите номер в международном формате: +998901234567');
        }
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: number,
          forceResendingToken: resendToken,
          verificationCompleted: (credential) async {
            try {
              final signedIn = await FirebaseAuth.instance.signInWithCredential(credential);
              await finishFirebaseLogin(signedIn);
            } catch (e) {
              if (mounted) setState(() => error = e.toString());
            }
          },
          verificationFailed: (exception) {
            if (mounted) setState(() { error = exception.message ?? exception.code; busy = false; });
          },
          codeSent: (id, token) {
            if (mounted) setState(() {
              verificationId = id;
              resendToken = token;
              requested = true;
              busy = false;
            });
          },
          codeAutoRetrievalTimeout: (id) { verificationId = id; },
          timeout: const Duration(seconds: 60),
        );
      } else {
        if (verificationId == null) throw StateError('Запросите SMS-код заново');
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId!, smsCode: code.text.trim());
        final signedIn = await FirebaseAuth.instance.signInWithCredential(credential);
        await finishFirebaseLogin(signedIn);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted && (requested || error != null)) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (userId != null) return RealChats(api: api, userId: userId!, onLogout: () {
      FirebaseAuth.instance.signOut();
      setState(() { api.token = null; userId = null; requested = false; verificationId = null; code.clear(); });
    });
    return Scaffold(
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30), children: [
          Center(child: Container(width: 108, height: 108,
            decoration: const BoxDecoration(color: Color(0xFF3390EC), shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 55))),
          const SizedBox(height: 30),
          Text(requested ? 'Подтверждение номера' : 'Ваш номер телефона',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 12),
          Text(requested
              ? 'Введите код из SMS, отправленный на ${phone.text.trim()}'
              : 'Пожалуйста, подтвердите код страны и введите номер телефона.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 34),
          if (!requested) TextField(
            key: const Key('phone-input'), controller: phone, enabled: !busy,
            keyboardType: TextInputType.phone, autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Номер телефона', hintText: '+998 90 123 45 67',
              prefixIcon: Icon(Icons.phone_outlined))),
          if (requested) TextField(
            key: const Key('sms-code-input'), controller: code, enabled: !busy,
            autofocus: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Код подтверждения',
              prefixIcon: Icon(Icons.lock_outline))),
          if (error != null) ...[
            const SizedBox(height: 14),
            Text(error!, textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          SizedBox(height: 52, child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3390EC)),
            onPressed: busy ? null : submit,
            child: busy ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(requested ? 'ВОЙТИ' : 'ПРОДОЛЖИТЬ',
                style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          )),
          if (requested) TextButton(onPressed: busy ? null : () =>
            setState(() { requested = false; code.clear(); error = null; }),
            child: const Text('Изменить номер телефона')),
          const SizedBox(height: 26),
          Text('SMS-код отправляется через Firebase Authentication.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ))),
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
  Future<void> newGroup() async {
    final title = TextEditingController();
    final members = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Создать группу'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Название группы')),
        TextField(controller: members, decoration: const InputDecoration(
          labelText: 'ID участников через запятую', helperText: 'UUID пользователей')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Создать')),
      ],
    ));
    final groupTitle = title.text.trim();
    final ids = members.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    title.dispose();
    members.dispose();
    if (result != true || groupTitle.isEmpty || ids.isEmpty) return;
    try {
      final group = await widget.api.request('POST', '/groups', {'title': groupTitle, 'member_ids': ids});
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        RealConversation(api: widget.api, chatId: group['id'] as String, userId: widget.userId)));
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
      IconButton(onPressed: newGroup, icon: const Icon(Icons.group_add_outlined), tooltip: 'Создать группу'),
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
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;
  @override
  void initState() { super.initState(); reload(); connectRealtime(); }
  void connectRealtime() {
    final token = widget.api.token;
    if (token == null) return;
    try {
      final uri = Uri.parse(serverUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://') + '/api/v1/ws');
      channel = WebSocketChannel.connect(uri);
      channel!.sink.add(jsonEncode({'token': token}));
      subscription = channel!.stream.listen((event) {
        try {
          final data = jsonDecode(event as String);
          if (data is Map && data['type'] == 'message' && data['data']?['chat_id'] == widget.chatId) reload();
        } catch (_) {}
      }, onError: (_) {}, cancelOnError: true);
    } catch (_) {}
  }
  @override
  void dispose() { subscription?.cancel(); channel?.sink.close(); input.dispose(); super.dispose(); }
  Future<void> reload() async {
    try {
      final result = await widget.api.request('GET', '/chats/${widget.chatId}/messages');
      if (mounted) setState(() { messages = result as List; error = null; });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
  }
  Future<void> messageActions(Map<String, dynamic> message) async {
    if (message['sender_id'] != widget.userId) return;
    final action = await showModalBottomSheet<String>(context: context, builder: (context) =>
      SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Редактировать'),
          onTap: () => Navigator.pop(context, 'edit')),
        ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Удалить'),
          onTap: () => Navigator.pop(context, 'delete')),
      ])));
    if (action == null) return;
    try {
      if (action == 'delete') {
        await widget.api.request('DELETE', '/messages/${message['id']}');
      } else {
        final editController = TextEditingController(text: message['text'].toString());
        final newText = await showDialog<String>(context: context, builder: (context) =>
          AlertDialog(title: const Text('Изменить сообщение'),
            content: TextField(controller: editController, autofocus: true, maxLines: 3),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(context, editController.text.trim()),
                child: const Text('Сохранить')),
            ]));
        editController.dispose();
        if (newText == null || newText.isEmpty) return;
        await widget.api.request('PATCH', '/messages/${message['id']}', {'text': newText});
      }
      await reload();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
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
            child: GestureDetector(
              onLongPress: () => messageActions(Map<String, dynamic>.from(msg as Map)),
              child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14)),
              child: Text(msg['text'].toString()),
            )),
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
