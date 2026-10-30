import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homestream_files/core/models.dart';
import 'package:homestream_files/core/prefs.dart';
import 'package:homestream_files/state/app_state.dart';
import 'package:homestream_files/state/pane.dart';
import 'package:homestream_files/ui/theme.dart';
import 'package:homestream_files/ui/widgets/file_pane.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Host implements PaneHost {
  @override
  Future<void> send(
    PaneController from,
    List<FileItem> items, {
    String? intoDir,
  }) async {}
  @override
  Future<void> osDrop(
    PaneController to,
    List<String> paths, {
    String? intoDir,
  }) async {}
  @override
  void openFile(PaneController c, FileItem e) {}
  @override
  bool canPaste(PaneController c) => false;
  @override
  void clip(PaneController c, List<FileItem> items, {required bool cut}) {}
  @override
  Future<void> paste(PaneController c, {String? intoDir}) async {}
}

void main() {
  // The pane once built itself inside itself (a closure captured a variable
  // that was reassigned), so rows never appeared. Keep a real render check.
  for (final grid in [false, true]) {
    testWidgets('local pane renders its rows (grid: $grid)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      prefs.gridView = grid;
      final app = AppState(prefs);
      final now = DateTime(2026, 10, 30, 12);
      final c = PaneController(remote: false, app: app)
        ..path = r'C:\'
        ..items = [
          FileItem(
            name: 'folder',
            path: r'C:\folder',
            isDir: true,
            mtime: now,
            count: 3,
          ),
          for (var i = 0; i < 5; i++)
            FileItem(
              name: 'file$i.txt',
              path: 'C:\\file$i.txt',
              isDir: false,
              size: i * 1000,
              mtime: now,
            ),
        ];
      tester.view.physicalSize = const Size(3439, 1391);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: Row(
                children: [
                  Expanded(
                    child: FilePane(
                      c: c,
                      host: _Host(),
                      title: 'Bu bilgisayar',
                      subtitle: '',
                      icon: Icons.computer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.text('file3.txt'), findsOneWidget);
      expect(find.text('folder'), findsOneWidget);
      // let debounced saves and other short timers finish
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await tester.pump(const Duration(seconds: 10));
    });
  }
}
