import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(dir.path);
  Hive.registerAdapter(ToDoItemAdapter());
  Hive.registerAdapter(ResetTypeAdapter());
  Hive.registerAdapter(PriorityAdapter());
  await initNotifications();
  runApp(MyApp());
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('app_icon');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

Future<void> scheduleNotification(String title, DateTime dueDate) async {
  if (dueDate.isBefore(DateTime.now())) return;

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'todo_channel',
    'Todo Notifications',
    importance: Importance.high,
    priority: Priority.high,
  );
  const NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.schedule(
    title.hashCode,
    'Task Due Soon',
    'Your task "$title" is due soon',
    dueDate.subtract(const Duration(hours: 1)),
    platformDetails,
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'To-Do List Resettable',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: ToDoListPage(),
    );
  }
}

@HiveType(typeId: 0)
class ToDoItem extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  bool isChecked;

  @HiveField(2)
  ResetType resetType;

  @HiveField(3)
  DateTime? customDate;

  @HiveField(4)
  String category;
  
  @HiveField(5)
  Priority priority;
  
  @HiveField(6)
  DateTime? dueDate;
  
  @HiveField(7)
  String notes;

  ToDoItem({
    required this.title,
    this.isChecked = false,
    this.resetType = ResetType.none,
    this.customDate,
    this.category = 'Default',
    this.priority = Priority.medium,
    this.dueDate,
    this.notes = '',
  });
}

@HiveType(typeId: 1)
enum ResetType {
  @HiveField(0)
  none,
  @HiveField(1)
  daily,
  @HiveField(2)
  weekly,
  @HiveField(3)
  customDate
}

@HiveType(typeId: 2)
enum Priority {
  @HiveField(0)
  low,
  @HiveField(1)
  medium,
  @HiveField(2)
  high
}

class ToDoListPage extends StatefulWidget {
  @override
  _ToDoListPageState createState() => _ToDoListPageState();
}

class _ToDoListPageState extends State<ToDoListPage> {
  late Box<ToDoItem> todoBox;
  String selectedCategory = 'Default';
  String searchQuery = '';
  bool showCompleted = true;
  Priority? filterPriority;
  SortMethod currentSortMethod = SortMethod.default_;

  @override
  void initState() {
    super.initState();
    openBox();
  }

  void openBox() async {
    todoBox = await Hive.openBox<ToDoItem>('todo');
    checkAndResetItems();
    setState(() {});
  }

  void checkAndResetItems() {
    DateTime now = DateTime.now();
    for (var item in todoBox.values) {
      switch (item.resetType) {
        case ResetType.daily:
          if (!isSameDay(item.customDate ?? now, now)) {
            item.isChecked = false;
            item.customDate = now;
            item.save();
          }
          break;
        case ResetType.weekly:
          if (item.customDate == null || now.difference(item.customDate!).inDays >= 7) {
            item.isChecked = false;
            item.customDate = now;
            item.save();
          }
          break;
        case ResetType.customDate:
          if (item.customDate != null && isSameDay(item.customDate!, now)) {
            item.isChecked = false;
            item.save();
          }
          break;
        default:
          break;
      }
    }
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void showResetSettingDialog(ToDoItem item) async {
    ResetType selectedReset = item.resetType;
    DateTime? selectedDate = item.customDate;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Set Reset Type"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<ResetType>(
              value: selectedReset,
              onChanged: (val) => setState(() => selectedReset = val!),
              items: ResetType.values
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.toString().split('.').last),
                      ))
                  .toList(),
            ),
            if (selectedReset == ResetType.customDate)
              TextButton(
                onPressed: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => selectedDate = picked);
                },
                child: Text(selectedDate == null
                    ? 'Select Date'
                    : DateFormat.yMd().format(selectedDate!)),
              )
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(
              onPressed: () {
                setState(() {
                  item.resetType = selectedReset;
                  item.customDate = selectedReset == ResetType.customDate
                      ? selectedDate
                      : DateTime.now();
                  item.save();
                });
                Navigator.pop(context);
              },
              child: Text('Save')),
        ],
      ),
    );
  }

  void showAddEditItemDialog({ToDoItem? item}) {
    final titleController = TextEditingController(text: item?.title ?? '');
    final categoryController = TextEditingController(text: item?.category ?? selectedCategory);
    final notesController = TextEditingController(text: item?.notes ?? '');
    
    Priority selectedPriority = item?.priority ?? Priority.medium;
    DateTime? selectedDueDate = item?.dueDate;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(item == null ? "Add New To-Do" : "Edit To-Do"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: titleController, decoration: InputDecoration(labelText: 'Title')),
                
                TextField(controller: categoryController, decoration: InputDecoration(labelText: 'Category')),
                
                SizedBox(height: 16),
                Text('Priority:'),
                SegmentedButton<Priority>(
                  segments: [
                    ButtonSegment(
                      value: Priority.low,
                      label: Text('Low'),
                      icon: Icon(Icons.arrow_downward),
                    ),
                    ButtonSegment(
                      value: Priority.medium,
                      label: Text('Medium'),
                      icon: Icon(Icons.remove),
                    ),
                    ButtonSegment(
                      value: Priority.high,
                      label: Text('High'),
                      icon: Icon(Icons.arrow_upward),
                    ),
                  ],
                  selected: {selectedPriority},
                  onSelectionChanged: (Set<Priority> newSelection) {
                    setState(() {
                      selectedPriority = newSelection.first;
                    });
                  },
                ),
                
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Due Date:'),
                    TextButton(
                      onPressed: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDueDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => selectedDueDate = picked);
                        }
                      },
                      child: Text(
                        selectedDueDate == null
                            ? 'Set Due Date'
                            : DateFormat.yMMMd().format(selectedDueDate!),
                      ),
                    ),
                    if (selectedDueDate != null)
                      IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          setState(() => selectedDueDate = null);
                        },
                      ),
                  ],
                ),
                
                SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(
                    labelText: 'Notes',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            TextButton(
              onPressed: () async {
                if (titleController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Title cannot be empty')),
                  );
                  return;
                }
                
                if (item == null) {
                  final newItem = ToDoItem(
                    title: titleController.text,
                    category: categoryController.text.isEmpty ? 'Default' : categoryController.text,
                    priority: selectedPriority,
                    dueDate: selectedDueDate,
                    notes: notesController.text,
                  );
                  await todoBox.add(newItem);
                  if (selectedDueDate != null) {
                    scheduleNotification(newItem.title, selectedDueDate!);
                  }
                } else {
                  item.title = titleController.text;
                  item.category = categoryController.text.isEmpty ? 'Default' : categoryController.text;
                  item.priority = selectedPriority;
                  item.dueDate = selectedDueDate;
                  item.notes = notesController.text;
                  await item.save();
                  if (selectedDueDate != null) {
                    scheduleNotification(item.title, selectedDueDate!);
                  }
                }
                setState(() {});
                Navigator.pop(context);
              },
              child: Text(item == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  void showDetailsDialog(ToDoItem item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Category: ${item.category}'),
            Text('Priority: ${item.priority.toString().split('.').last}'),
            if (item.dueDate != null)
              Text('Due: ${DateFormat.yMMMd().format(item.dueDate!)}'),
            if (item.resetType != ResetType.none)
              Text('Reset: ${item.resetType.toString().split('.').last}'),
            SizedBox(height: 8),
            if (item.notes.isNotEmpty) ...[
              Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(item.notes),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              showAddEditItemDialog(item: item);
            },
            child: Text('Edit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Hive.isBoxOpen('todo')) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    List<String> categories = todoBox.values.map((e) => e.category).toSet().toList()..sort();
    List<ToDoItem> allItems = todoBox.values.where((e) => e.category == selectedCategory).toList();
    
    // Apply filters
    List<ToDoItem> filteredItems = allItems.where((item) {
      bool matchesSearch = searchQuery.isEmpty || 
          item.title.toLowerCase().contains(searchQuery.toLowerCase());
      bool matchesCompletionFilter = showCompleted || !item.isChecked;
      bool matchesPriorityFilter = filterPriority == null || item.priority == filterPriority;
      
      return matchesSearch && matchesCompletionFilter && matchesPriorityFilter;
    }).toList();
    
    // Apply sorting
    switch (currentSortMethod) {
      case SortMethod.default_:
        // Default is already sorted by index in Hive
        break;
      case SortMethod.alphabetical:
        filteredItems.sort((a, b) => a.title.compareTo(b.title));
        break;
      case SortMethod.priority:
        filteredItems.sort((a, b) => b.priority.index.compareTo(a.priority.index));
        break;
      case SortMethod.dueDate:
        filteredItems.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('To-Do List'),
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context, 
                delegate: TodoSearchDelegate(todoBox.values.toList(), (item) {
                  showDetailsDialog(item);
                }),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Categories',
            onSelected: (val) => setState(() => selectedCategory = val),
            itemBuilder: (context) => categories
                .map((cat) => PopupMenuItem(value: cat, child: Text(cat)))
                .toList(),
            icon: Icon(Icons.folder),
          ),
          PopupMenuButton<String>(
            tooltip: 'Options',
            onSelected: (value) {
              if (value == 'filter') {
                _showFilterDialog();
              } else if (value == 'sort') {
                _showSortDialog();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'filter', child: Text('Filter')),
              PopupMenuItem(value: 'sort', child: Text('Sort')),
            ],
            icon: Icon(Icons.more_vert),
          ),
        ],
        bottom: searchQuery.isNotEmpty ? PreferredSize(
          preferredSize: Size.fromHeight(40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(child: Text('Search: "$searchQuery"')),
                IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      searchQuery = '';
                    });
                  },
                ),
              ],
            ),
          ),
        ) : null,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddEditItemDialog(),
        child: Icon(Icons.add),
      ),
      body: filteredItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    searchQuery.isNotEmpty
                        ? 'No tasks match your search'
                        : 'No tasks in this category',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                var item = filteredItems[index];
                return ListTile(
                  leading: Checkbox(
                    value: item.isChecked,
                    onChanged: (val) {
                      setState(() {
                        item.isChecked = val!;
                        item.save();
                      });
                    },
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      decoration: item.isChecked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: _buildSubtitle(item),
                  tileColor: _getPriorityColor(item.priority, item.isChecked, context),
                  onTap: () => showDetailsDialog(item),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit),
                        onPressed: () => showAddEditItemDialog(item: item),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete),
                        onPressed: () async {
                          await item.delete();
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSubtitle(ToDoItem item) {
    List<String> subtitles = [];
    
    if (item.dueDate != null) {
      bool isOverdue = item.dueDate!.isBefore(DateTime.now()) && !item.isChecked;
      subtitles.add('Due: ${DateFormat.yMMMd().format(item.dueDate!)}');
      if (isOverdue) {
        return Text(
          subtitles.join(' · '),
          style: TextStyle(color: Colors.red),
        );
      }
    }
    
    if (item.resetType != ResetType.none) {
      subtitles.add('Resets: ${item.resetType.toString().split('.').last}');
    }
    
    if (subtitles.isEmpty) {
      return null;
    }
    
    return Text(subtitles.join(' · '));
  }

  Color _getPriorityColor(Priority priority, bool isChecked, BuildContext context) {
    if (isChecked) return Colors.transparent;
    
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    switch (priority) {
      case Priority.high:
        return isDarkMode ? Color(0xFF4A2828) : Color(0xFFFFF0F0);
      case Priority.medium:
        return isDarkMode ? Color(0xFF2D3A2A) : Color(0xFFF0FFF0);
      case Priority.low:
        return Colors.transparent;
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Filter Tasks'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  title: Text('Show Completed Tasks'),
                  value: showCompleted,
                  onChanged: (value) {
                    setDialogState(() {
                      showCompleted = value!;
                    });
                  },
                ),
                SizedBox(height: 16),
                Text('Filter by Priority:'),
                DropdownButton<Priority?>(
                  isExpanded: true,
                  value: filterPriority,
                  items: [
                    DropdownMenuItem<Priority?>(
                      value: null,
                      child: Text('All Priorities'),
                    ),
                    ...Priority.values.map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.toString().split('.').last),
                    )),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      filterPriority = value;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    // filters are already updated in the dialog
                  });
                  Navigator.pop(context);
                },
                child: Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Sort Tasks'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final method in SortMethod.values)
              RadioListTile<SortMethod>(
                title: Text(_getSortMethodName(method)),
                value: method,
                groupValue: currentSortMethod,
                onChanged: (value) {
                  setState(() {
                    currentSortMethod = value!;
                    Navigator.pop(context);
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  String _getSortMethodName(SortMethod method) {
    switch (method) {
      case SortMethod.default_:
        return 'Default';
      case SortMethod.alphabetical:
        return 'Alphabetical';
      case SortMethod.priority:
        return 'Priority';
      case SortMethod.dueDate:
        return 'Due Date';
    }
  }
}

enum SortMethod {
  default_,
  alphabetical,
  priority,
  dueDate,
}

class TodoSearchDelegate extends SearchDelegate<String> {
  final List<ToDoItem> items;
  final Function(ToDoItem) onItemSelected;

  TodoSearchDelegate(this.items, this.onItemSelected);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      )
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return buildSearchResults();
  }

  Widget buildSearchResults() {
    final results = query.isEmpty
        ? items
        : items.where((item) =>
            item.title.toLowerCase().contains(query.toLowerCase()) ||
            item.notes.toLowerCase().contains(query.toLowerCase()) ||
            item.category.toLowerCase().contains(query.toLowerCase())).toList();

    return results.isEmpty
        ? Center(child: Text('No results found'))
        : ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final item = results[index];
              return ListTile(
                title: Text(item.title),
                subtitle: Text(item.category),
                trailing: item.dueDate != null
                    ? Text(DateFormat.yMd().format(item.dueDate!))
                    : null,
                onTap: () {
                  onItemSelected(item);
                  close(context, item.title);
                },
              );
            },
          );
  }
}

class ToDoItemAdapter extends TypeAdapter<ToDoItem> {
  @override
  final int typeId = 0;

  @override
  ToDoItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    
    return ToDoItem(
      title: fields[0] as String,
      isChecked: fields[1] as bool,
      resetType: fields[2] as ResetType,
      customDate: fields[3] as DateTime?,
      category: fields[4] as String? ?? 'Default',
      priority: fields.containsKey(5) ? fields[5] as Priority : Priority.medium,
      dueDate: fields.containsKey(6) ? fields[6] as DateTime? : null,
      notes: fields.containsKey(7) ? fields[7] as String : '',
    );
  }

  @override
  void write(BinaryWriter writer, ToDoItem obj) {
    writer.writeByte(8);
    writer.writeByte(0);
    writer.write(obj.title);
    writer.writeByte(1);
    writer.write(obj.isChecked);
    writer.writeByte(2);
    writer.write(obj.resetType);
    writer.writeByte(3);
    writer.write(obj.customDate);
    writer.writeByte(4);
    writer.write(obj.category);
    writer.writeByte(5);
    writer.write(obj.priority);
    writer.writeByte(6);
    writer.write(obj.dueDate);
    writer.writeByte(7);
    writer.write(obj.notes);
  }
}

class ResetTypeAdapter extends TypeAdapter<ResetType> {
  @override
  final int typeId = 1;

  @override
  ResetType read(BinaryReader reader) => ResetType.values[reader.readInt()];

  @override
  void write(BinaryWriter writer, ResetType obj) => writer.writeInt(obj.index);
}

class PriorityAdapter extends TypeAdapter<Priority> {
  @override
  final int typeId = 2;
  
  @override
  Priority read(BinaryReader reader) => Priority.values[reader.readInt()];
  
  @override
  void write(BinaryWriter writer, Priority obj) => writer.writeInt(obj.index);
}
