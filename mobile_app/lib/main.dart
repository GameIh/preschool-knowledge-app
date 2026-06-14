import 'package:flutter/material.dart';

import 'app_database.dart';
import 'auth_models.dart';
import 'auth_service.dart';
import 'models.dart';
import 'sync_service.dart';

const _text = Color(0xFF1F2937);
const _muted = Color(0xFF6B7280);
const _accent = Color(0xFF38BDF8);
const _accent2 = Color(0xFFA78BFA);
const _good = Color(0xFF34D399);
const _warn = Color(0xFFFBBF24);
const _border = Color(0x1F1F2937);
const _card = Color(0xF2FFFFFF);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.database;
  final authenticated = await AuthService.instance.initialize();
  runApp(PreschoolKnowledgeApp(initiallyAuthenticated: authenticated));
}

class PreschoolKnowledgeApp extends StatelessWidget {
  const PreschoolKnowledgeApp({super.key, this.initiallyAuthenticated = false});

  final bool initiallyAuthenticated;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'База знаний дошкольника',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Roboto',
        textTheme: Theme.of(
          context,
        ).textTheme.apply(bodyColor: _text, displayColor: _text),
      ),
      home: KnowledgeRoot(initiallyAuthenticated: initiallyAuthenticated),
    );
  }
}

class KnowledgeRoot extends StatefulWidget {
  const KnowledgeRoot({super.key, required this.initiallyAuthenticated});

  final bool initiallyAuthenticated;

  @override
  State<KnowledgeRoot> createState() => _KnowledgeRootState();
}

class _KnowledgeRootState extends State<KnowledgeRoot> {
  late bool _authorized;

  @override
  void initState() {
    super.initState();
    _authorized = widget.initiallyAuthenticated;
    if (_authorized) {
      AppDatabase.instance.setActiveOwnerId(
        AuthService.instance.currentUser!.id,
      );
    }
  }

  void _authenticated() {
    AppDatabase.instance.setActiveOwnerId(AuthService.instance.currentUser!.id);
    setState(() => _authorized = true);
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    AppDatabase.instance.setActiveOwnerId(null);
    if (mounted) {
      setState(() => _authorized = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _authorized
        ? MainShell(onLogout: _logout)
        : LoginScreen(onAuthenticated: _authenticated);
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _db = AppDatabase.instance;
  var _index = 0;
  var _version = 0;
  var _children = <ChildProfile>[];
  ChildProfile? _selectedChild;

  @override
  void initState() {
    super.initState();
    _reloadChildren();
  }

  Future<void> _reloadChildren({int? selectId}) async {
    final children = await _db.getChildren();
    if (!mounted) {
      return;
    }

    ChildProfile? selected;
    if (children.isNotEmpty) {
      selected = children.firstWhere(
        (child) => child.id == (selectId ?? _selectedChild?.id),
        orElse: () => children.first,
      );
    }

    setState(() {
      _children = children;
      _selectedChild = selected;
      _version++;
    });
  }

  void _selectChild(ChildProfile child) {
    setState(() {
      _selectedChild = child;
      _version++;
    });
  }

  void _refreshData() {
    setState(() => _version++);
  }

  Future<void> _openActivity(Activity activity) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActivityDetailScreen(
          activity: activity,
          child: _selectedChild,
          onSaved: () {
            setState(() {
              _index = 2;
              _version++;
            });
          },
        ),
      ),
    );
    if (mounted) {
      _refreshData();
    }
  }

  Future<void> _openSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SyncScreen(
          onSynced: () async => _reloadChildren(),
          onSessionExpired: widget.onLogout,
        ),
      ),
    );
    if (mounted) {
      _refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        key: ValueKey('home-$_version'),
        child: _selectedChild,
        onOpenCatalog: () => setState(() => _index = 1),
        onOpenProfile: () => setState(() => _index = 2),
        onOpenSync: _openSync,
        onOpenActivity: _openActivity,
      ),
      CatalogPage(
        key: ValueKey('catalog-$_version'),
        child: _selectedChild,
        onOpenActivity: _openActivity,
      ),
      ProfilePage(
        key: ValueKey('profile-$_version'),
        authUser: AuthService.instance.currentUser!,
        children: _children,
        selectedChild: _selectedChild,
        onSelectChild: _selectChild,
        onChildCreated: (id) => _reloadChildren(selectId: id),
        onChildChanged: () => _reloadChildren(selectId: _selectedChild?.id),
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          border: const Border(top: BorderSide(color: _border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            backgroundColor: Colors.transparent,
            indicatorColor: _accent.withValues(alpha: 0.18),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Главная',
              ),
              NavigationDestination(
                icon: Icon(Icons.list_alt_outlined),
                selectedIcon: Icon(Icons.list_alt_rounded),
                label: 'Каталог',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Профиль',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onAuthenticated});

  final VoidCallback onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _registerMode = false;
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    if (email.isEmpty || password.isEmpty || (_registerMode && name.isEmpty)) {
      setState(() => _error = 'Заполните обязательные поля');
      return;
    }
    if (_registerMode && password.length < 8) {
      setState(() => _error = 'Пароль должен содержать не менее 8 символов');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_registerMode) {
        await AuthService.instance.register(
          name: name,
          email: email,
          password: password,
        );
      } else {
        await AuthService.instance.login(email: email, password: password);
      }
      if (mounted) {
        widget.onAuthenticated();
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось подключиться. Проверьте интернет и попробуйте снова.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'База знаний дошкольника',
      subtitle: 'Развитие • упражнения • прогресс',
      children: [
        const HeroPanel(),
        const SizedBox(height: 12),
        SoftCard(
          child: Column(
            children: [
              if (_registerMode) ...[
                AppTextField(
                  label: 'Имя',
                  controller: _nameController,
                  hint: 'например: Регина',
                  icon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 10),
              ],
              AppTextField(
                label: 'Электронная почта',
                controller: _emailController,
                hint: 'например: parent@mail.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 10),
              AppTextField(
                label: 'Пароль',
                controller: _passwordController,
                hint: 'пароль',
                icon: Icons.lock_outline_rounded,
                obscureText: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TwoColumns(
                children: [
                  SoftButton(
                    label: _submitting
                        ? 'Подождите'
                        : _registerMode
                        ? 'Создать аккаунт'
                        : 'Войти',
                    icon: _registerMode
                        ? Icons.person_add_alt_1_rounded
                        : Icons.login_rounded,
                    primary: true,
                    onPressed: _submitting ? null : _submit,
                  ),
                  SoftButton(
                    label: _registerMode
                        ? 'У меня есть аккаунт'
                        : 'Регистрация',
                    icon: _registerMode
                        ? Icons.login_rounded
                        : Icons.person_add_alt_1_rounded,
                    ghost: true,
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                            _registerMode = !_registerMode;
                            _error = null;
                          }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.child,
    required this.onOpenCatalog,
    required this.onOpenProfile,
    required this.onOpenSync,
    required this.onOpenActivity,
  });

  final ChildProfile? child;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenSync;
  final ValueChanged<Activity> onOpenActivity;

  Future<_HomeData> _loadData() async {
    final db = AppDatabase.instance;
    return _HomeData(
      recommendations: await db.getRecommended(child),
      logs: await db.getLogs(childId: child?.id, limit: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Главная',
      subtitle: 'Подбор занятий и быстрые действия',
      action: SoftChipButton(
        label: 'Обновить',
        icon: Icons.sync_rounded,
        onPressed: onOpenSync,
      ),
      children: [
        FutureBuilder<_HomeData>(
          future: _loadData(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LoadingCard();
            }
            final data = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    text: 'Выбран ребёнок: ',
                                    children: [
                                      TextSpan(
                                        text: child?.name ?? 'не выбран',
                                        style: const TextStyle(
                                          color: _accent,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  child == null
                                      ? 'Добавьте профиль ребёнка в разделе профиля'
                                      : 'Возраст: ${child!.ageLabel} • ${child!.notes ?? 'цели не указаны'}',
                                  style: _smallMuted,
                                ),
                              ],
                            ),
                          ),
                          const Pill(label: 'профиль'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TwoColumns(
                        children: [
                          SoftButton(
                            label: 'Подобрать упражнение',
                            icon: Icons.search_rounded,
                            primary: true,
                            onPressed: onOpenCatalog,
                          ),
                          SoftButton(
                            label: 'История занятий',
                            icon: Icons.history_rounded,
                            onPressed: onOpenProfile,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SectionTitle('Рекомендации на сегодня'),
                                SizedBox(height: 4),
                                Text(
                                  '3 коротких упражнения на 10-15 минут',
                                  style: _smallMuted,
                                ),
                              ],
                            ),
                          ),
                          const Pill(label: 'быстро', icon: Icons.bolt_rounded),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (data.recommendations.isEmpty)
                        const EmptyState(
                          icon: Icons.search_off_rounded,
                          text: 'Подходящих упражнений пока нет.',
                        )
                      else
                        ...data.recommendations.map(
                          (activity) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ActivityTile(
                              activity: activity,
                              onTap: () => onOpenActivity(activity),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle('Последние занятия'),
                      const SizedBox(height: 12),
                      if (data.logs.isEmpty)
                        const EmptyState(
                          icon: Icons.event_note_rounded,
                          text: 'История появится после выполнения задания.',
                        )
                      else
                        ...data.logs.map((log) => LogTile(log: log)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.child,
    required this.onOpenActivity,
  });

  final ChildProfile? child;
  final ValueChanged<Activity> onOpenActivity;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _searchController = TextEditingController();
  String? _domain;
  var _shortOnly = false;
  var _sort = 'recommended';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_CatalogData> _loadData() async {
    final db = AppDatabase.instance;
    return _CatalogData(
      domains: await db.getDomainNames(),
      activities: await db.getActivities(
        query: _searchController.text,
        domain: _domain,
        ageMonths: widget.child?.ageMonths,
        shortOnly: _shortOnly,
        sort: _sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Каталог',
      subtitle: 'Фильтр по возрасту, направлениям и тегам',
      children: [
        FutureBuilder<_CatalogData>(
          future: _loadData(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LoadingCard();
            }
            final data = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTextField(
                        label: 'Поиск',
                        controller: _searchController,
                        hint: 'Например: звук Р, внимание, счёт',
                        icon: Icons.search_rounded,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SelectablePill(
                            label: widget.child?.ageLabel ?? 'любой возраст',
                            selected: widget.child != null,
                            icon: Icons.child_care_rounded,
                          ),
                          SelectablePill(
                            label: 'короткие',
                            selected: _shortOnly,
                            icon: Icons.star_rounded,
                            onTap: () =>
                                setState(() => _shortOnly = !_shortOnly),
                          ),
                          if (_domain != null)
                            SelectablePill(
                              label: _domain!,
                              selected: true,
                              icon: Icons.close_rounded,
                              onTap: () => setState(() => _domain = null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: data.domains
                            .map(
                              (domain) => SelectablePill(
                                label: domain,
                                selected: _domain == domain,
                                onTap: () => setState(
                                  () => _domain = _domain == domain
                                      ? null
                                      : domain,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: _softDecoration(radius: 14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _sort,
                              isExpanded: true,
                              icon: const Icon(Icons.sort_rounded),
                              items: const [
                                DropdownMenuItem(
                                  value: 'recommended',
                                  child: Text('Сортировка: рекомендованные'),
                                ),
                                DropdownMenuItem(
                                  value: 'duration',
                                  child: Text('Сортировка: сначала короткие'),
                                ),
                                DropdownMenuItem(
                                  value: 'difficulty',
                                  child: Text('Сортировка: по сложности'),
                                ),
                                DropdownMenuItem(
                                  value: 'title',
                                  child: Text('Сортировка: по названию'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _sort = value);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: SectionTitle('Подходящие упражнения'),
                          ),
                          Pill(label: 'найдено: ${data.activities.length}'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (data.activities.isEmpty)
                        const EmptyState(
                          icon: Icons.search_off_rounded,
                          text: 'По этим условиям ничего не найдено.',
                        )
                      else
                        ...data.activities.map(
                          (activity) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ActivityTile(
                              activity: activity,
                              onTap: () => widget.onOpenActivity(activity),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({
    super.key,
    required this.activity,
    required this.child,
    required this.onSaved,
  });

  final Activity activity;
  final ChildProfile? child;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Карточка упражнения',
      subtitle: 'Описание, шаги выполнения, отметка прогресса',
      action: SoftChipButton(
        label: 'Каталог',
        icon: Icons.arrow_back_rounded,
        onPressed: () => Navigator.of(context).pop(),
      ),
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${activity.domainLabel} • ${activity.ageLabel} • ${activity.durationMin} минут',
                          style: _smallMuted,
                        ),
                      ],
                    ),
                  ),
                  Pill(label: 'сложность: ${activity.difficulty}/5'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Pill(
                    label: activity.materialsLabel,
                    icon: Icons.backpack_rounded,
                  ),
                  ...activity.tags.map((tag) => Pill(label: 'тег: $tag')),
                ],
              ),
              const AppDivider(),
              if (activity.shortDesc != null &&
                  activity.shortDesc!.isNotEmpty) ...[
                Text(activity.shortDesc!, style: _bodyMuted),
                const AppDivider(),
              ],
              const SectionTitle('Как выполнять'),
              const SizedBox(height: 8),
              Text(
                activity.instruction,
                style: _bodyMuted.copyWith(height: 1.5),
              ),
              if (activity.safetyNotes != null &&
                  activity.safetyNotes!.trim().isNotEmpty) ...[
                const AppDivider(),
                const SectionTitle('Примечание'),
                const SizedBox(height: 8),
                Text(activity.safetyNotes!, style: _bodyMuted),
              ],
              const AppDivider(),
              TwoColumns(
                children: [
                  SoftButton(
                    label: 'Отметить выполнено',
                    icon: Icons.check_circle_outline_rounded,
                    primary: true,
                    onPressed: child == null
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => DoneScreen(
                                  activity: activity,
                                  child: child!,
                                  onSaved: onSaved,
                                ),
                              ),
                            );
                          },
                  ),
                  SoftButton(
                    label: 'На главную',
                    icon: Icons.home_rounded,
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                  ),
                ],
              ),
              if (child == null) ...[
                const SizedBox(height: 10),
                const Text(
                  'Чтобы сохранить результат, сначала добавьте ребёнка в профиле.',
                  style: _smallMuted,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class DoneScreen extends StatefulWidget {
  const DoneScreen({
    super.key,
    required this.activity,
    required this.child,
    required this.onSaved,
  });

  final Activity activity;
  final ChildProfile child;
  final VoidCallback onSaved;

  @override
  State<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<DoneScreen> {
  final _commentController = TextEditingController();
  var _rating = 5.0;
  var _saving = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await AppDatabase.instance.addActivityLog(
      childId: widget.child.id,
      activityId: widget.activity.id,
      status: 'done',
      rating: _rating.round(),
      comment: _commentController.text,
    );
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    widget.onSaved();
    Navigator.of(context).popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      const SnackBar(content: Text('Занятие сохранено в историю')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Готово',
      subtitle: 'Отметка о выполнении будет сохранена',
      action: SoftChipButton(
        label: 'Назад',
        icon: Icons.arrow_back_rounded,
        onPressed: () => Navigator.of(context).pop(),
      ),
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.activity.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text('Ребёнок: ${widget.child.name}', style: _smallMuted),
              const AppDivider(),
              const SectionTitle('Оценка занятия'),
              Slider(
                value: _rating,
                min: 1,
                max: 5,
                divisions: 4,
                label: _rating.round().toString(),
                activeColor: _accent,
                onChanged: (value) => setState(() => _rating = value),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('1', style: _smallMuted),
                  Text('5', style: _smallMuted),
                ],
              ),
              const SizedBox(height: 10),
              AppTextField(
                label: 'Комментарий',
                controller: _commentController,
                hint: 'что получилось, что было сложно',
                icon: Icons.edit_note_rounded,
              ),
              const SizedBox(height: 12),
              TwoColumns(
                children: [
                  SoftButton(
                    label: _saving ? 'Сохраняю' : 'Сохранить',
                    icon: Icons.save_rounded,
                    primary: true,
                    onPressed: _saving ? null : _save,
                  ),
                  SoftButton(
                    label: 'На главную',
                    icon: Icons.home_rounded,
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.authUser,
    required this.children,
    required this.selectedChild,
    required this.onSelectChild,
    required this.onChildCreated,
    required this.onChildChanged,
    required this.onLogout,
  });

  final AuthUser authUser;
  final List<ChildProfile> children;
  final ChildProfile? selectedChild;
  final ValueChanged<ChildProfile> onSelectChild;
  final ValueChanged<int> onChildCreated;
  final VoidCallback onChildChanged;
  final Future<void> Function() onLogout;

  Future<_ProfileData> _loadData() async {
    final db = AppDatabase.instance;
    return _ProfileData(
      logs: await db.getLogs(childId: selectedChild?.id, limit: 20),
      domains: await db.getDomainNames(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Профиль',
      subtitle: 'Дети, цели и история занятий',
      children: [
        FutureBuilder<_ProfileData>(
          future: _loadData(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const LoadingCard();
            }
            final data = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoftCard(
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle_rounded, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              authUser.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(authUser.email, style: _smallMuted),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Выйти из аккаунта',
                        onPressed: onLogout,
                        icon: const Icon(Icons.logout_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (children.length > 1)
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      value: selectedChild?.id,
                                      isExpanded: true,
                                      items: children
                                          .map(
                                            (child) => DropdownMenuItem(
                                              value: child.id,
                                              child: Text(child.name),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (id) {
                                        final child = children
                                            .where((item) => item.id == id)
                                            .firstOrNull;
                                        if (child != null) {
                                          onSelectChild(child);
                                        }
                                      },
                                    ),
                                  )
                                else
                                  Text(
                                    selectedChild?.name ?? 'Профиль не создан',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  selectedChild == null
                                      ? 'Добавьте ребёнка для ведения истории'
                                      : '${selectedChild!.ageLabel} • ${selectedChild!.notes ?? 'заметки не указаны'}',
                                  style: _smallMuted,
                                ),
                              ],
                            ),
                          ),
                          const Pill(
                            label: 'ребёнок',
                            icon: Icons.child_care_rounded,
                          ),
                        ],
                      ),
                      const AppDivider(),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SoftButton(
                            label: 'Добавить ребёнка',
                            icon: Icons.person_add_alt_1_rounded,
                            onPressed: () => _showAddChildDialog(context),
                          ),
                          SoftButton(
                            label: 'Цели развития',
                            icon: Icons.flag_rounded,
                            onPressed: selectedChild == null
                                ? null
                                : () => _showGoalsDialog(context, data.domains),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: SectionTitle('История занятий'),
                          ),
                          const Pill(label: 'последние'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (data.logs.isEmpty)
                        const EmptyState(
                          icon: Icons.history_rounded,
                          text: 'Пока нет сохранённых занятий.',
                        )
                      else
                        ...data.logs.map((log) => LogTile(log: log)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _showAddChildDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final ageController = TextEditingController();
    final notesController = TextEditingController();

    final createdId = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Новый профиль'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Имя',
                controller: nameController,
                hint: 'например: Маша',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 10),
              AppTextField(
                label: 'Возраст в месяцах',
                controller: ageController,
                hint: 'например: 54',
                icon: Icons.cake_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              AppTextField(
                label: 'Заметки и цели',
                controller: notesController,
                hint: 'речь, внимание, моторика',
                icon: Icons.edit_note_rounded,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  return;
                }
                final id = await AppDatabase.instance.createChild(
                  name: name,
                  ageMonths: int.tryParse(ageController.text.trim()),
                  notes: notesController.text,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(id);
                }
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    ageController.dispose();
    notesController.dispose();

    if (createdId != null) {
      onChildCreated(createdId);
    }
  }

  Future<void> _showGoalsDialog(
    BuildContext context,
    List<String> domains,
  ) async {
    final child = selectedChild;
    if (child == null) {
      return;
    }

    final notesController = TextEditingController(text: child.notes ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Цели развития'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: domains
                    .map(
                      (domain) => Pill(label: domain, icon: Icons.flag_rounded),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Заметки',
                controller: notesController,
                hint: 'например: речь + внимание',
                icon: Icons.edit_note_rounded,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await AppDatabase.instance.updateChildNotes(
                  child.id,
                  notesController.text,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
    notesController.dispose();
    onChildChanged();
  }
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({
    super.key,
    required this.onSynced,
    required this.onSessionExpired,
  });

  final Future<void> Function() onSynced;
  final Future<void> Function() onSessionExpired;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _db = AppDatabase.instance;
  var _syncing = false;
  String? _message;

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _message = null;
    });

    try {
      final result = await SyncService(_db, AuthService.instance).synchronize();
      if (!mounted) {
        return;
      }
      await widget.onSynced();
      setState(() {
        _message = result.inserted + result.updated + result.deleted > 0
            ? 'Материалы обновлены.'
            : 'У вас уже установлены актуальные материалы.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is AuthException) {
        Navigator.of(context).pop();
        await widget.onSessionExpired();
        return;
      }
      setState(
        () => _message =
            'Не удалось обновить материалы. Проверьте подключение к интернету и попробуйте снова.',
      );
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Обновления',
      subtitle: 'Новые задания и материалы',
      action: SoftChipButton(
        label: 'Главная',
        icon: Icons.arrow_back_rounded,
        onPressed: () => Navigator.of(context).pop(),
      ),
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Обновить материалы'),
              const SizedBox(height: 4),
              const Text(
                'Загрузите новые упражнения и рекомендации для занятий.',
                style: _bodyMuted,
              ),
              const SizedBox(height: 12),
              SoftButton(
                label: _syncing ? 'Обновляем' : 'Обновить',
                icon: Icons.sync_rounded,
                primary: true,
                onPressed: _syncing ? null : _sync,
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: _bodyMuted),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TopBar(title: title, subtitle: subtitle, action: action),
                const SizedBox(height: 14),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF7ED),
            Color(0xFFF0F9FF),
            Color(0xFFFDF2F8),
            Color(0xFFF0FDF4),
          ],
        ),
      ),
      child: child,
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: _smallMuted),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: _softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Добро пожаловать',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Подбирайте развивающие задания, сохраняйте результаты и обновляйте базу знаний.',
            style: _bodyMuted,
          ),
          const SizedBox(height: 12),
          TwoColumns(
            children: const [
              StatBox(label: 'Встроенных заданий', value: '12+'),
              StatBox(label: 'Направлений развития', value: '6'),
            ],
          ),
        ],
      ),
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: _softShadow,
      ),
      child: child,
    );
  }
}

class LoadingCard extends StatelessWidget {
  const LoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(label, style: _smallMuted),
        ),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.92),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _accent, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class SoftButton extends StatelessWidget {
  const SoftButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.primary = false,
    this.ghost = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: primary ? _accent.withValues(alpha: 0.55) : _border,
      ),
      gradient: primary
          ? LinearGradient(
              colors: [
                _accent.withValues(alpha: enabled ? 0.30 : 0.12),
                _accent2.withValues(alpha: enabled ? 0.22 : 0.10),
              ],
            )
          : null,
      color: primary
          ? null
          : Colors.white.withValues(alpha: ghost ? 0.55 : 0.88),
      boxShadow: ghost ? null : _softShadowSmall,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: decoration,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: enabled ? _text : _muted),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: enabled ? _text : _muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SoftChipButton extends StatelessWidget {
  const SoftChipButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: _softDecoration(radius: 999),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _softDecoration(radius: 999, shadow: false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: _muted),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: _text.withValues(alpha: 0.70),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class SelectablePill extends StatelessWidget {
  const SelectablePill({
    super.key,
    required this.label,
    required this.selected,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? _accent.withValues(alpha: 0.5) : _border,
            ),
            color: selected
                ? _accent.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.78),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TwoColumns extends StatelessWidget {
  const TwoColumns({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children) ...[
                child,
                if (child != children.last) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (final child in children) ...[
              Expanded(child: child),
              if (child != children.last) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class StatBox extends StatelessWidget {
  const StatBox({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _softDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _smallMuted),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.activity, required this.onTap});

  final Activity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InfoTile(
      icon: _domainIcon(activity.domains.firstOrNull),
      title: activity.title,
      subtitle:
          '${activity.domainLabel} • ${activity.durationMin} минут • ${activity.materialsLabel}',
      onTap: onTap,
    );
  }
}

class LogTile extends StatelessWidget {
  const LogTile({super.key, required this.log});

  final ActivityLog log;

  @override
  Widget build(BuildContext context) {
    final done = log.status == 'done';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InfoTile(
        icon: done ? Icons.check_rounded : Icons.refresh_rounded,
        title: log.activityTitle ?? 'Занятие',
        subtitle:
            '${done ? 'выполнено' : 'пропущено'} • ${formatDate(log.dateTime)}${log.rating == null ? '' : ' • оценка: ${log.rating}/5'}',
        tint: done ? _good : _warn,
      ),
    );
  }
}

class InfoTile extends StatelessWidget {
  const InfoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.tint = _accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: _softDecoration(radius: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                  gradient: LinearGradient(
                    colors: [
                      tint.withValues(alpha: 0.24),
                      _accent2.withValues(alpha: 0.16),
                    ],
                  ),
                ),
                child: Icon(icon, color: _text),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _smallMuted.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _softDecoration(radius: 18, shadow: false),
      child: Row(
        children: [
          Icon(icon, color: _muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: _bodyMuted)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
    );
  }
}

class AppDivider extends StatelessWidget {
  const AppDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 12),
      color: _border,
    );
  }
}

class _HomeData {
  const _HomeData({required this.recommendations, required this.logs});

  final List<Activity> recommendations;
  final List<ActivityLog> logs;
}

class _CatalogData {
  const _CatalogData({required this.domains, required this.activities});

  final List<String> domains;
  final List<Activity> activities;
}

class _ProfileData {
  const _ProfileData({required this.logs, required this.domains});

  final List<ActivityLog> logs;
  final List<String> domains;
}

const _smallMuted = TextStyle(color: _muted, fontSize: 12);
const _bodyMuted = TextStyle(color: _muted, fontSize: 13);

List<BoxShadow> get _softShadow => [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.10),
    blurRadius: 26,
    offset: const Offset(0, 12),
  ),
];

List<BoxShadow> get _softShadowSmall => [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.08),
    blurRadius: 18,
    offset: const Offset(0, 8),
  ),
];

BoxDecoration _softDecoration({required double radius, bool shadow = true}) {
  return BoxDecoration(
    color: Colors.white.withValues(alpha: 0.86),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _border),
    boxShadow: shadow ? _softShadowSmall : null,
  );
}

IconData _domainIcon(String? domain) {
  return switch (domain) {
    'Речь' => Icons.record_voice_over_rounded,
    'Внимание' => Icons.visibility_rounded,
    'Мелкая моторика' => Icons.back_hand_rounded,
    'Логика' => Icons.calculate_rounded,
    'Память' => Icons.psychology_rounded,
    'Сенсорика' => Icons.palette_rounded,
    _ => Icons.extension_rounded,
  };
}

String formatDate(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'нет данных';
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }

  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(parsed.day)}.${two(parsed.month)}.${parsed.year} ${two(parsed.hour)}:${two(parsed.minute)}';
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
