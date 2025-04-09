import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  Hive.registerAdapter(ToDoItemAdapter());
  Hive.registerAdapter(ResetTypeAdapter());
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'To-Do List Resettable',
      theme: ThemeData(primarySwatch: Colors.blue),
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

  ToDoItem({
    required this.title,
    this.isChecked = false,
    this.resetType = ResetType.none,
    this.customDate,
    this.category = 'Default',
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

class ToDoListPage extends StatefulWidget {
  @override
  _ToDoListPageState createState() => _ToDoListPageState();
}

class _ToDoListPageState extends State<ToDoListPage> {
  late Box<ToDoItem> todoBox;
  String selectedCategory = 'Default';

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

  void showAddItemDialog() {
    final titleController = TextEditingController();
    final categoryController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Add New To-Do"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: InputDecoration(labelText: 'Title')),
            TextField(controller: categoryController, decoration: InputDecoration(labelText: 'Category')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(
              onPressed: () async {
                final newItem = ToDoItem(
                  title: titleController.text,
                  category: categoryController.text.isEmpty ? 'Default' : categoryController.text,
                );
                await todoBox.add(newItem);
                setState(() {});
                Navigator.pop(context);
              },
              child: Text('Add')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<String> categories = todoBox.values.map((e) => e.category).toSet().toList();
    List<ToDoItem> items = todoBox.values.where((e) => e.category == selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('To-Do List Resettable'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) => setState(() => selectedCategory = val),
            itemBuilder: (context) => categories
                .map((cat) => PopupMenuItem(value: cat, child: Text(cat)))
                .toList(),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showAddItemDialog,
        child: Icon(Icons.add),
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          var item = items[index];
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
            title: Text(item.title),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.settings),
                  onPressed: () => showResetSettingDialog(item),
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
}

class ToDoItemAdapter extends TypeAdapter<ToDoItem> {
  @override
  final int typeId = 0;

  @override
  ToDoItem read(BinaryReader reader) {
    return ToDoItem(
      title: reader.readString(),
      isChecked: reader.readBool(),
      resetType: ResetType.values[reader.readInt()],
      customDate: reader.readBool() ? reader.readDateTime() : null,
      category: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, ToDoItem obj) {
    writer.writeString(obj.title);
    writer.writeBool(obj.isChecked);
    writer.writeInt(obj.resetType.index);
    writer.writeBool(obj.customDate != null);
    if (obj.customDate != null) writer.writeDateTime(obj.customDate!);
    writer.writeString(obj.category);
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
